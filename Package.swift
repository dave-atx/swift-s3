// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftS3",
    platforms: [
        .macOS(.v15),
        .iOS(.v18)
    ],
    products: [
        .library(
            name: "SwiftS3",
            targets: ["SwiftS3"]
        ),
        .executable(
            name: "ss3",
            targets: ["ss3"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0")
    ],
    targets: [
        .target(
            name: "SwiftS3",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "SwiftS3Tests",
            dependencies: ["SwiftS3"]
        ),
        .executableTarget(
            name: "ss3",
            dependencies: [
                "SwiftS3",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "ss3Tests",
            dependencies: ["ss3"]
        ),
        .testTarget(
            name: "IntegrationTests",
            dependencies: ["SwiftS3"]
        ),
        .testTarget(
            name: "ss3IntegrationTests",
            dependencies: ["ss3"]
        )
    ]
)
