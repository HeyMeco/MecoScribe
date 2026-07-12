// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MecoScribe",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MecoScribeCore",
            targets: ["MecoScribeCore"]
        ),
        .executable(
            name: "mecoscribe",
            targets: ["MecoScribeCLI"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "MecoScribeCore",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            resources: [
                .process("Resources"),
            ]
        ),
        .executableTarget(
            name: "MecoScribeCLI",
            dependencies: ["MecoScribeCore"]
        ),
    ]
)
