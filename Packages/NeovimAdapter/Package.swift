// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NeovimAdapter",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "NeovimAdapter", targets: ["NeovimAdapter"])
    ],
    dependencies: [
        .package(path: "../SmaltiCore")
    ],
    targets: [
        .target(
            name: "NeovimAdapter",
            dependencies: [.product(name: "SmaltiCore", package: "SmaltiCore")]),
        .testTarget(
            name: "NeovimAdapterTests",
            dependencies: [
                "NeovimAdapter",
                .product(name: "SmaltiCore", package: "SmaltiCore"),
                .product(name: "SmaltiCoreTestSupport", package: "SmaltiCore"),
            ]),
    ]
)
