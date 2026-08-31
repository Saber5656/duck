// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "duck",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "DuckCore",
            targets: ["DuckCore"]
        ),
        .executable(
            name: "duck",
            targets: ["duck"]
        )
    ],
    targets: [
        .target(
            name: "DuckCore"
        ),
        .executableTarget(
            name: "duck",
            dependencies: ["DuckCore"]
        ),
        .testTarget(
            name: "DuckCoreTests",
            dependencies: ["DuckCore"]
        )
    ]
)
