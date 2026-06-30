// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CoLearner",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "CoLearnerCore",
            targets: ["CoLearnerCore"]
        ),
        .executable(
            name: "CoLearner",
            targets: ["CoLearnerApp"]
        )
    ],
    targets: [
        .target(
            name: "CoLearnerCore"
        ),
        .executableTarget(
            name: "CoLearnerApp",
            dependencies: ["CoLearnerCore"]
        ),
        .testTarget(
            name: "CoLearnerCoreTests",
            dependencies: ["CoLearnerCore"]
        )
    ]
)
