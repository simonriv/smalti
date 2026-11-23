// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ProjectContextAdapter",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "ProjectContextAdapter", targets: ["ProjectContextAdapter"])
    ],
    dependencies: [
        .package(path: "../SmaltiCore")
    ],
    targets: [
        .target(
            name: "ProjectContextAdapter",
            dependencies: [.product(name: "SmaltiCore", package: "SmaltiCore")]),
        .testTarget(
            name: "ProjectContextAdapterTests",
            dependencies: [
                "ProjectContextAdapter",
                .product(name: "SmaltiCore", package: "SmaltiCore"),
                .product(name: "SmaltiCoreTestSupport", package: "SmaltiCore"),
            ]),
    ]
)
