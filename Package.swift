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
        )
    ],
    targets: [
        .target(
            name: "SwiftS3",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "SwiftS3Tests",
            dependencies: ["SwiftS3"]
        )
    ]
)
