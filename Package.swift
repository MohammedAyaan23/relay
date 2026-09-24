// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Relay",
    platforms: [.macOS("26.0")],
    dependencies: [
        // Pinned to a commit: FluidUse's README says 0.2.1, but the newest tag is v0.2.0.
        .package(url: "https://github.com/FluidInference/FluidUse.git", revision: "e0d4215ae395a877e9d11bbb75bb26413137ab05"),
    ],
    targets: [
        .target(name: "Extraction"),
        .testTarget(name: "ExtractionTests", dependencies: ["Extraction"]),
        .target(name: "Actions"),
        .testTarget(name: "ActionsTests", dependencies: ["Actions"], exclude: ["Fixtures"]),
        .target(name: "Routing", dependencies: [.product(name: "FluidUse", package: "FluidUse")]),
        .testTarget(name: "RoutingTests", dependencies: ["Routing"], exclude: ["phrases.json"]),
    ]
)
