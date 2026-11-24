// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DiagnosticsAdapter",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "DiagnosticsAdapter", targets: ["DiagnosticsAdapter"])
    ],
    dependencies: [
        .package(path: "../SmaltiCore")
    ],
    targets: [
        .target(
            name: "DiagnosticsAdapter",
            dependencies: [.product(name: "SmaltiCore", package: "SmaltiCore")]),
        .testTarget(
            name: "DiagnosticsAdapterTests",
            dependencies: [
                "DiagnosticsAdapter",
                .product(name: "SmaltiCore", package: "SmaltiCore"),
                .product(name: "SmaltiCoreTestSupport", package: "SmaltiCore"),
            ]),
    ]
)
