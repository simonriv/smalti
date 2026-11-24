// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ImageIOAdapter",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "ImageIOAdapter", targets: ["ImageIOAdapter"])
    ],
    dependencies: [
        .package(path: "../SmaltiCore")
    ],
    targets: [
        .target(
            name: "ImageIOAdapter",
            dependencies: [.product(name: "SmaltiCore", package: "SmaltiCore")]),
        .testTarget(
            name: "ImageIOAdapterTests",
            dependencies: [
                "ImageIOAdapter",
                .product(name: "SmaltiCore", package: "SmaltiCore"),
                .product(name: "SmaltiCoreTestSupport", package: "SmaltiCore"),
            ]),
    ]
)
