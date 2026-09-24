// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftSourcePlayground",
    platforms: [.iOS(.v15), .macOS(.v10_15)],
    products: [.library(name: "SwiftSourcePlayground", targets: ["SwiftSourcePlayground"])],
    dependencies: [.package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "603.0.1")],
    targets: [
        .target(name: "SwiftSourcePlayground", dependencies: [
            .product(name: "SwiftSyntax", package: "swift-syntax"),
            .product(name: "SwiftParser", package: "swift-syntax"),
            .product(name: "SwiftParserDiagnostics", package: "swift-syntax")
        ]),
        .testTarget(name: "SwiftSourcePlaygroundTests", dependencies: ["SwiftSourcePlayground"])
    ]
)
