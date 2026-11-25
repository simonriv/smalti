// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OpenCodeHarnessAdapter",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "OpenCodeHarnessAdapter", targets: ["OpenCodeHarnessAdapter"])
    ],
    dependencies: [
        .package(path: "../SmaltiCore"),
        .package(path: "../SQLiteReader"),
    ],
    targets: [
        .target(
            name: "OpenCodeHarnessAdapter",
            dependencies: [
                .product(name: "SmaltiCore", package: "SmaltiCore"),
                .product(name: "SQLiteReader", package: "SQLiteReader"),
            ]),
        .testTarget(
            name: "OpenCodeHarnessAdapterTests",
            dependencies: [
                "OpenCodeHarnessAdapter",
                .product(name: "SmaltiCore", package: "SmaltiCore"),
                .product(name: "SmaltiCoreTestSupport", package: "SmaltiCore"),
            ],
            resources: [.copy("Fixtures")]),
    ]
)
