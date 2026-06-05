// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Compose",
    platforms: [.iOS(.v26), .macOS(.v26), .tvOS(.v26)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "Compose",
            targets: ["Compose"],
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.0"),
        .package(url: "https://github.com/apple/swift-atomics.git", from: "1.3.0"),
        .package(url: "https://github.com/pointfreeco/swift-perception.git", from: "2.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "Compose",
            dependencies: [
                //.product(name: "TrailingElementsModule", package: "swift-collections"),
                .product(name: "DequeModule", package: "swift-collections"),
                .product(name: "Atomics", package: "swift-atomics"),
                .product(name: "Perception", package: "swift-perception"),
            ],
//            swiftSettings: [.define("BITSET_USE_DYNAMIC_ARRAY")]
        ),
        .testTarget(
            name: "ComposeTests",
            dependencies: [
                "Compose",
                .product(name: "DequeModule", package: "swift-collections"),
                .product(name: "Perception", package: "swift-perception"),
            ]
        ),
        .testTarget(
            name: "ComposePerformanceTests",
            dependencies: [
                "Compose",
            ]
        ),
    ],
    swiftLanguageModes: [SwiftLanguageMode.v6]
)
