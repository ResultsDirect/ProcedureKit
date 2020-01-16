// swift-tools-version:5.0

import PackageDescription

let pkg = Package(name: "ProcedureKit")

pkg.swiftLanguageVersions = [
    .v5,
]

pkg.platforms = [
    .macOS(.v10_11),
    .iOS(.v10),
    .tvOS(.v10),
    .watchOS(.v3),
]

pkg.products = [
    .library(name: "ProcedureKit", targets: ["ProcedureKit"]),
    .library(name: "ProcedureKitCloud", targets: ["ProcedureKitCloud"]),
    .library(name: "ProcedureKitCoreData", targets: ["ProcedureKitCoreData"]),
    .library(name: "ProcedureKitLocation", targets: ["ProcedureKitLocation"]),
    .library(name: "ProcedureKitMac", targets: ["ProcedureKitMac"]),
    .library(name: "ProcedureKitMobile", targets: ["ProcedureKitMobile"]),
    .library(name: "ProcedureKitNetwork", targets: ["ProcedureKitNetwork"]),
    .library(name: "TestingProcedureKit", targets: ["TestingProcedureKit"])
]

pkg.targets = [
    .target(name: "ProcedureKit"),
    .target(name: "ProcedureKitCloud", dependencies: ["ProcedureKit"]),
    .target(name: "ProcedureKitCoreData", dependencies: ["ProcedureKit"]),
    .target(name: "ProcedureKitLocation", dependencies: ["ProcedureKit"]),
    .target(name: "ProcedureKitMac", dependencies: ["ProcedureKit"]),
    .target(name: "ProcedureKitMobile", dependencies: ["ProcedureKit"]),
    .target(name: "ProcedureKitNetwork", dependencies: ["ProcedureKit"]),
    .target(name: "TestingProcedureKit", dependencies: ["ProcedureKit"])
]
