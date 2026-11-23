// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SmaltiCore",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "SmaltiCore", targets: ["SmaltiCore"]),
        .library(name: "SmaltiCoreTestSupport", targets: ["SmaltiCoreTestSupport"]),
    ],
    targets: [
        .target(name: "SmaltiCore"),
        .target(name: "SmaltiCoreTestSupport", dependencies: ["SmaltiCore"]),
        .testTarget(name: "SmaltiCoreTests", dependencies: ["SmaltiCore", "SmaltiCoreTestSupport"]),
    ]
)
