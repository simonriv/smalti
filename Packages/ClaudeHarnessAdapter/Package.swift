// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ClaudeHarnessAdapter",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "ClaudeHarnessAdapter", targets: ["ClaudeHarnessAdapter"])
    ],
    dependencies: [
        .package(path: "../SmaltiCore")
    ],
    targets: [
        .target(
            name: "ClaudeHarnessAdapter",
            dependencies: [.product(name: "SmaltiCore", package: "SmaltiCore")]),
        .testTarget(
            name: "ClaudeHarnessAdapterTests",
            dependencies: [
                "ClaudeHarnessAdapter",
                .product(name: "SmaltiCore", package: "SmaltiCore"),
                .product(name: "SmaltiCoreTestSupport", package: "SmaltiCore"),
            ],
            resources: [.copy("Fixtures")]),
    ]
)
