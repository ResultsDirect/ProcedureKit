//
//  ProcedureKit
//
//  Copyright © 2015-2018 ProcedureKit. All rights reserved.
//

#if !os(watchOS)

#if SWIFT_PACKAGE
    import ProcedureKit
    import Foundation
#endif

import SystemConfiguration

public protocol NetworkResilience {

    /**
     The number of attempts to make for the
     network request. It represents the total number
     of attempts which should be made.

     - returns: a Int
     */
    var maximumNumberOfAttempts: Int { get }

    /**
     The timeout backoff wait strategy defines the time between
     retry attempts in the event of a network timout.
     Use `.Immediate` to indicate no time between retry attempts.

     - returns: a WaitStrategy
     */
    var backoffStrategy: WaitStrategy { get }

    /**
     A request timeout, which if specified indicates the maximum
     amount of time to wait for a response.

     - returns: a TimeInterval
     */
    var requestTimeout: TimeInterval? { get }

    /**
     Some HTTP status codes should be treated as errors, and
     retried

     - parameter statusCode: an Int
     - returns: a Bool, to indicate that the
     */
    func shouldRetry(forResponseWithHTTPStatusCode statusCode: HTTPStatusCode) -> Bool
}

public struct DefaultNetworkResilience: NetworkResilience {

    public let maximumNumberOfAttempts: Int

    public let backoffStrategy: WaitStrategy

    public let requestTimeout: TimeInterval?

    public init(maximumNumberOfAttempts: Int = 3, backoffStrategy: WaitStrategy = .incrementing(initial: 2, increment: 2), requestTimeout: TimeInterval? = 8.0) {
        self.maximumNumberOfAttempts = maximumNumberOfAttempts
        self.backoffStrategy = backoffStrategy
        self.requestTimeout = requestTimeout
    }

    public func shouldRetry(forResponseWithHTTPStatusCode statusCode: HTTPStatusCode) -> Bool {
        switch statusCode {
        case let code where code.isServerError:
            return true
        case .requestTimeout, .tooManyRequests:
            return true
        default:
            return false
        }
    }
}

public enum ProcedureKitNetworkResiliencyError: Error {
    case receivedErrorStatusCode(HTTPStatusCode)
}

class NetworkReachabilityWaitProcedure: Procedure {

    let reachability: SystemReachability
    let connectivity: Reachability.Connectivity

    init(reachability: SystemReachability, via connectivity: Reachability.Connectivity = .any) {
        self.reachability = reachability
        self.connectivity = connectivity
        super.init()
    }

    override func execute() {
        reachability.whenReachable(via: connectivity) { [weak self] in self?.finish() }
    }
}

open class NetworkRecovery<T: Procedure> where T: NetworkOperation {

    let resilience: NetworkResilience
    let connectivity: Reachability.Connectivity
    fileprivate var reachability: SystemReachability = Reachability.Manager.shared

    var max: Int { return resilience.maximumNumberOfAttempts }

    var wait: WaitStrategy { return resilience.backoffStrategy }

    public init(resilience: NetworkResilience, connectivity: Reachability.Connectivity) {
        self.resilience = resilience
        self.connectivity = connectivity
    }

    open func recover(withInfo info: RetryFailureInfo<T>, payload: RepeatProcedurePayload<T>) -> RepeatProcedurePayload<T>? {

        let networkResponse = info.operation.makeNetworkResponse()

        // Check to see if we should wait for a network reachability change before retrying
        if shouldWaitForReachabilityChange(givenNetworkResponse: networkResponse) {
            let waiter = NetworkReachabilityWaitProcedure(reachability: reachability, via: connectivity)
            payload.operation.addDependency(waiter)
            info.addOperations(waiter)
            return RepeatProcedurePayload(operation: payload.operation, delay: nil, configure: payload.configure)
        }

        // Check if the resiliency behavior indicates a retry
        guard shouldRetry(givenNetworkResponse: networkResponse) else { return nil }

        return payload
    }

    func shouldWaitForReachabilityChange(givenNetworkResponse networkResponse: ProcedureKitNetworkResponse) -> Bool {
        guard let networkError = networkResponse.error else { return false }
        return networkError.waitForReachabilityChangeBeforeRetrying
    }

    open func shouldRetry(givenNetworkResponse networkResponse: ProcedureKitNetworkResponse) -> Bool {

        // Check that we've actually got a network error & suggested delay
        if let networkError = networkResponse.error {

            // Check to see if we have a transient or timeout network error - retry with suggested delay
            if networkError.isTransientError || networkError.isTimeoutError {
                return true
            }
        }

        // Check to see if we have an http error code
        guard let statusCode = networkResponse.httpStatusCode, statusCode.isClientError || statusCode.isServerError else {
            return false
        }

        // Query the network resilience type to determine the behavior.
        return resilience.shouldRetry(forResponseWithHTTPStatusCode: statusCode)
    }
}

open class NetworkProcedure<T: Procedure>: RetryProcedure<T> where T: NetworkOperation {

    let recovery: NetworkRecovery<T>

    internal var reachability: SystemReachability {
        get { return recovery.reachability }
        set { recovery.reachability = newValue }
    }

    public init<OperationIterator>(dispatchQueue: DispatchQueue? = nil, recovery: NetworkRecovery<T>, iterator base: OperationIterator) where OperationIterator: IteratorProtocol, OperationIterator.Element == T {
        self.recovery = recovery
        super.init(dispatchQueue: dispatchQueue, max: recovery.max, wait: recovery.wait, iterator: base, retry: recovery.recover(withInfo:payload:))
        if let timeout = recovery.resilience.requestTimeout {
            appendConfigureBlock { $0.addObserver(TimeoutObserver(by: timeout)) }
        }
    }

    public convenience init<OperationIterator>(dispatchQueue: DispatchQueue? = nil, resilience: NetworkResilience = DefaultNetworkResilience(), connectivity: Reachability.Connectivity = .any, iterator base: OperationIterator) where OperationIterator: IteratorProtocol, OperationIterator.Element == T {
        self.init(dispatchQueue: dispatchQueue, recovery: NetworkRecovery<T>(resilience: resilience, connectivity: connectivity), iterator: base)
    }

    public convenience init(dispatchQueue: DispatchQueue = DispatchQueue.default, resilience: NetworkResilience = DefaultNetworkResilience(), connectivity: Reachability.Connectivity = .any, body: @escaping () -> T?) {
        self.init(dispatchQueue: dispatchQueue, resilience: resilience, connectivity: connectivity, iterator: AnyIterator(body))
    }

    open override func child(_ child: Procedure, willFinishWithError error: Error?) {
        var networkError = error

        // Ultimately, always call super to correctly manage the operation lifecycle.
        defer { super.child(child, willFinishWithError: networkError) }

        // Check that the operation is the current one.
        guard child == current else { return }

        // If we have an error let RetryProcedure (super) deal with it by returning here
        guard error == nil else { return }

        // Create a network response from the network operation
        let networkResponse = current.makeNetworkResponse()

        // Check to see if this network response should be retried
        guard recovery.shouldRetry(givenNetworkResponse: networkResponse), let statusCode = networkResponse.httpStatusCode else { return }

        // Create resiliency error
        let resiliencyError: ProcedureKitNetworkResiliencyError = .receivedErrorStatusCode(statusCode)

        // Set the network errors
        networkError = resiliencyError
    }
}

#endif

public extension InputProcedure where Input: Equatable {

    @discardableResult func injectPayload<Dependency: OutputProcedure>(fromNetwork dependency: Dependency) -> Self where Dependency.Output: HTTPPayloadResponseProtocol, Dependency.Output.Payload == Input {
        return injectResult(from: dependency) { http in
            guard let payload = http.payload else { throw ProcedureKitError.requirementNotSatisfied() }
            return payload
        }
    }
}
