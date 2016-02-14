//
//  TimeoutObserverTests.swift
//  Operations
//
//  Created by Daniel Thorpe on 27/06/2015.
//  Copyright © 2015 Daniel Thorpe. All rights reserved.
//

import XCTest
@testable import Operations

class TimeoutObserverTests: OperationTests {

    func test__timeout_observer() {
        let expectation = expectationWithDescription("Test: \(__FUNCTION__)")

        let operation = TestOperation(delay: 0.5)
        operation.addObserver(TimeoutObserver(timeout: 0.1))

        var receivedErrors: [ErrorType] = []
        operation.addObserver(FinishedObserver { _, errors in
            receivedErrors = errors
        })

        addCompletionBlockToTestOperation(operation, withExpectation: expectation)
        runOperation(operation)
        waitForExpectationsWithTimeout(2, handler: nil)

        XCTAssertEqual(receivedErrors.count, 1)
    }
}
