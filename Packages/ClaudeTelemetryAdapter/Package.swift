// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ClaudeTelemetryAdapter",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "ClaudeTelemetryAdapter", targets: ["ClaudeTelemetryAdapter"])
    ],
    dependencies: [
        .package(path: "../SmaltiCore"),
        .package(path: "../JSONLReader"),
    ],
    targets: [
        .target(
            name: "ClaudeTelemetryAdapter",
            dependencies: [
                .product(name: "SmaltiCore", package: "SmaltiCore"),
                .product(name: "JSONLReader", package: "JSONLReader"),
            ]),
        .testTarget(
            name: "ClaudeTelemetryAdapterTests",
            dependencies: [
                "ClaudeTelemetryAdapter",
                .product(name: "SmaltiCore", package: "SmaltiCore"),
                .product(name: "SmaltiCoreTestSupport", package: "SmaltiCore"),
            ],
            exclude: ["Fixtures"]),
    ]
)
