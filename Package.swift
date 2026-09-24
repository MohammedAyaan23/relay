// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Relay",
    platforms: [.macOS("26.0")],
    targets: [
        .target(name: "Extraction"),
        .testTarget(name: "ExtractionTests", dependencies: ["Extraction"]),
    ]
)
