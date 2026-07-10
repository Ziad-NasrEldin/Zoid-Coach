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
        .library(name: "ZoidCoachCore", targets: ["ZoidCoachCore"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/Ebullioscopic/AtollExtensionKit",
            revision: "296562051f4ee8fec55aaca14782b21b8e63cafa"
        )
    ],
    targets: [
        .target(
            name: "ZoidCoachCore",
            path: "Sources/ZoidCoachCore"
        ),
        .target(
            name: "ZoidCoachInfrastructure",
            dependencies: [
                "ZoidCoachCore",
                .product(name: "AtollExtensionKit", package: "AtollExtensionKit")
            ],
            path: "Sources/ZoidCoachInfrastructure"
        ),
        .executableTarget(
            name: "ZoidCoachApp",
            dependencies: [
                "ZoidCoachCore",
                "ZoidCoachInfrastructure",
                .product(name: "AtollExtensionKit", package: "AtollExtensionKit")
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
            dependencies: ["ZoidCoachApp", "ZoidCoachCore", "ZoidCoachInfrastructure"],
            path: "Tests/ZoidCoachAppTests"
        )
    ]
)
