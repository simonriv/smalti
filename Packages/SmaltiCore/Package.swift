// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SmaltiCore",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "SmaltiCore", targets: ["SmaltiCore"])
    ],
    targets: [
        .target(name: "SmaltiCore"),
        .testTarget(name: "SmaltiCoreTests", dependencies: ["SmaltiCore"]),
    ]
)
