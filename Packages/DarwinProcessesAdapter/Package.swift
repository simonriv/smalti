// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DarwinProcessesAdapter",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "DarwinProcessesAdapter", targets: ["DarwinProcessesAdapter"])
    ],
    dependencies: [
        .package(path: "../SmaltiCore")
    ],
    targets: [
        .target(
            name: "DarwinProcessesAdapter",
            dependencies: [.product(name: "SmaltiCore", package: "SmaltiCore")]),
        .testTarget(
            name: "DarwinProcessesAdapterTests",
            dependencies: [
                "DarwinProcessesAdapter",
                .product(name: "SmaltiCore", package: "SmaltiCore"),
                .product(name: "SmaltiCoreTestSupport", package: "SmaltiCore"),
            ]),
    ]
)
