// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ZoidCoach",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ZoidCoach", targets: ["ZoidCoachApp"])
    ],
    targets: [
        .executableTarget(
            name: "ZoidCoachApp",
            path: "Sources/ZoidCoachApp"
        ),
        .testTarget(
            name: "ZoidCoachAppTests",
            dependencies: ["ZoidCoachApp"],
            path: "Tests/ZoidCoachAppTests"
        )
    ]
)
