// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FileSessionAdapter",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "FileSessionAdapter", targets: ["FileSessionAdapter"])
    ],
    dependencies: [
        .package(path: "../SmaltiCore")
    ],
    targets: [
        .target(
            name: "FileSessionAdapter",
            dependencies: [.product(name: "SmaltiCore", package: "SmaltiCore")]),
        .testTarget(
            name: "FileSessionAdapterTests",
            dependencies: [
                "FileSessionAdapter",
                .product(name: "SmaltiCore", package: "SmaltiCore"),
                .product(name: "SmaltiCoreTestSupport", package: "SmaltiCore"),
            ],
            resources: [.copy("Fixtures")]),
    ]
)
