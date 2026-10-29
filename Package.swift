// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MecoScribe",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "mecoscribe",
            targets: ["MecoScribeCLI"]
        ),
        .executable(
            name: "MecoScribeApp",
            targets: ["MecoScribeApp"]
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
            ]
        ),
        .executableTarget(
            name: "MecoScribeCLI",
            dependencies: [
                "MecoScribeCore",
                .product(name: "FluidAudio", package: "FluidAudio"),
            ]
        ),
        .executableTarget(
            name: "MecoScribeApp",
            dependencies: [
                "MecoScribeCore",
            ],
            resources: [
                .copy("Resources/MecoScribe.icns"),
            ]
        ),
        .testTarget(
            name: "MecoScribeAppTests",
            dependencies: ["MecoScribeApp", "MecoScribeCore"]
        ),
    ]
)
