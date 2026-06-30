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
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", branch: "main"),
    ],
    targets: [
        .executableTarget(
            name: "MecoScribeCLI",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
            ]
        ),
    ]
)
