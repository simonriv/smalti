// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "JSONLReader",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "JSONLReader", targets: ["JSONLReader"])
    ],
    targets: [
        .target(name: "JSONLReader"),
        .testTarget(name: "JSONLReaderTests", dependencies: ["JSONLReader"]),
    ]
)
