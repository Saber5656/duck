// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "DuckVolumeVADSpike",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "DuckVADSpike", targets: ["DuckVADSpike"]),
        .executable(name: "VADHarness", targets: ["VADHarness"]),
        .library(name: "VADCore", targets: ["VADCore"])
    ],
    targets: [
        .target(
            name: "VADCore"
        ),
        .executableTarget(
            name: "DuckVADSpike",
            dependencies: ["VADCore"],
            linkerSettings: [
                .linkedFramework("Accelerate"),
                .linkedFramework("AVFoundation")
            ]
        ),
        .executableTarget(
            name: "VADHarness",
            dependencies: ["VADCore"]
        )
    ]
)
