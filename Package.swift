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
    dependencies: [
        .package(
            url: "https://github.com/Ebullioscopic/AtollExtensionKit",
            revision: "296562051f4ee8fec55aaca14782b21b8e63cafa"
        )
    ],
    targets: [
        .executableTarget(
            name: "ZoidCoachApp",
            dependencies: [
                .product(name: "AtollExtensionKit", package: "AtollExtensionKit")
            ],
            path: "Sources/ZoidCoachApp"
        ),
        .testTarget(
            name: "ZoidCoachAppTests",
            dependencies: ["ZoidCoachApp"],
            path: "Tests/ZoidCoachAppTests"
        )
    ]
)
