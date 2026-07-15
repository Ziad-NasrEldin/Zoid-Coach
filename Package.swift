// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ZoidCoach",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ZoidCoach", targets: ["ZoidCoachApp"]),
        .executable(name: "ZoidCoachAgent", targets: ["ZoidCoachAgent"]),
        .library(
            name: "ZoidCoachCore",
            targets: ["ZoidCoachCore", "ZoidCoachInfrastructure"]
        ),
        .library(name: "ZoidCoachInfrastructure", targets: ["ZoidCoachInfrastructure"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "ZoidCoachCore",
            path: "Sources/ZoidCoachCore"
        ),
        .target(
            name: "ZoidCoachInfrastructure",
            dependencies: [
                "ZoidCoachCore"
            ],
            path: "Sources/ZoidCoachInfrastructure"
        ),
        .executableTarget(
            name: "ZoidCoachApp",
            dependencies: [
                "ZoidCoachCore",
                "ZoidCoachInfrastructure"
            ],
            path: "Sources/ZoidCoachApp"
        ),
        .executableTarget(
            name: "ZoidCoachAgent",
            dependencies: ["ZoidCoachCore", "ZoidCoachInfrastructure"],
            path: "Sources/ZoidCoachAgent"
        ),
        .testTarget(
            name: "ZoidCoachAppTests",
            dependencies: ["ZoidCoachApp", "ZoidCoachAgent", "ZoidCoachCore", "ZoidCoachInfrastructure"],
            path: "Tests/ZoidCoachAppTests"
        )
    ]
)
