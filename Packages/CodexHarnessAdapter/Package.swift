// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CodexHarnessAdapter",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "CodexHarnessAdapter", targets: ["CodexHarnessAdapter"])
    ],
    dependencies: [
        .package(path: "../SmaltiCore"),
        .package(path: "../SQLiteReader"),
    ],
    targets: [
        .target(
            name: "CodexHarnessAdapter",
            dependencies: [
                .product(name: "SmaltiCore", package: "SmaltiCore"),
                .product(name: "SQLiteReader", package: "SQLiteReader"),
            ]),
        .testTarget(
            name: "CodexHarnessAdapterTests",
            dependencies: [
                "CodexHarnessAdapter",
                .product(name: "SmaltiCore", package: "SmaltiCore"),
                .product(name: "SmaltiCoreTestSupport", package: "SmaltiCore"),
            ],
            resources: [.copy("Fixtures")]),
    ]
)
