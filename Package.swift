// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "archive-integrity",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "Engine", targets: ["Engine"]),
        .executable(name: "sentinel", targets: ["sentinel"]),
    ],
    dependencies: [
        .package(url: "https://github.com/thecoolwinter/SwiftBlake3.git", from: "0.1.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "Engine",
            dependencies: [
                .product(name: "Blake3", package: "SwiftBlake3"),
            ]
        ),
        .executableTarget(
            name: "sentinel",
            dependencies: [
                "Engine",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "EngineTests",
            dependencies: ["Engine"]
        ),
    ]
)
