// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AntigravityHarnessAdapter",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "AntigravityHarnessAdapter", targets: ["AntigravityHarnessAdapter"])
    ],
    dependencies: [
        .package(path: "../SmaltiCore"),
        .package(path: "../SQLiteReader"),
    ],
    targets: [
        .target(
            name: "AntigravityHarnessAdapter",
            dependencies: [
                .product(name: "SmaltiCore", package: "SmaltiCore"),
                .product(name: "SQLiteReader", package: "SQLiteReader"),
            ]),
        .testTarget(
            name: "AntigravityHarnessAdapterTests",
            dependencies: [
                "AntigravityHarnessAdapter",
                .product(name: "SmaltiCore", package: "SmaltiCore"),
                .product(name: "SmaltiCoreTestSupport", package: "SmaltiCore"),
            ],
            resources: [.copy("Fixtures")]),
    ]
)
