// swift-tools-version: 5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftWABackupAPI",
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "SwiftWABackupAPI",
            targets: ["SwiftWABackupAPI"]),
        .executable(
            name: "SwiftWABackupCLI",
            targets: ["SwiftWABackupCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.3")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "SwiftWABackupAPI",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
        .executableTarget(
            name: "SwiftWABackupCLI",
            dependencies: ["SwiftWABackupAPI"]),
        .testTarget(
            name: "SwiftWABackupAPITests",
            dependencies: ["SwiftWABackupAPI", "SwiftWABackupCLI"]),
    ]
)
