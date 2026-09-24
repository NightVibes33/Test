// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftFileRunner",
    platforms: [.iOS(.v17), .macOS(.v10_15)],
    products: [.library(name: "SwiftFileRunner", targets: ["SwiftFileRunner"])],
    dependencies: [
        // Use Apple's parser implementation to validate and, in the next
        // interpreter increment, evaluate real Swift syntax trees. This is
        // parsing only; imported code is never compiled or loaded as a binary.
        .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "603.0.1")
    ],
    targets: [
        .target(
            name: "SwiftFileRunner",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftParserDiagnostics", package: "swift-syntax")
            ],
            path: "SwiftFileRunner",
            sources: ["Interpreter.swift"]
        ),
        .testTarget(name: "SwiftFileRunnerTests", dependencies: ["SwiftFileRunner"], path: "SwiftFileRunnerTests")
    ]
)
