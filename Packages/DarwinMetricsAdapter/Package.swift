// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DarwinMetricsAdapter",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "DarwinMetricsAdapter", targets: ["DarwinMetricsAdapter"])
    ],
    dependencies: [
        .package(path: "../SmaltiCore")
    ],
    targets: [
        .target(
            name: "DarwinMetricsAdapter",
            dependencies: [.product(name: "SmaltiCore", package: "SmaltiCore")]),
        .testTarget(
            name: "DarwinMetricsAdapterTests",
            dependencies: [
                "DarwinMetricsAdapter",
                .product(name: "SmaltiCore", package: "SmaltiCore"),
                .product(name: "SmaltiCoreTestSupport", package: "SmaltiCore"),
            ]),
    ]
)
