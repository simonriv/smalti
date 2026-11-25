// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OTLPReceiverAdapter",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "OTLPReceiverAdapter", targets: ["OTLPReceiverAdapter"])
    ],
    dependencies: [
        .package(path: "../SmaltiCore")
    ],
    targets: [
        .target(
            name: "OTLPReceiverAdapter",
            dependencies: [.product(name: "SmaltiCore", package: "SmaltiCore")]),
        .testTarget(
            name: "OTLPReceiverAdapterTests",
            dependencies: [
                "OTLPReceiverAdapter",
                .product(name: "SmaltiCore", package: "SmaltiCore"),
                .product(name: "SmaltiCoreTestSupport", package: "SmaltiCore"),
            ],
            resources: [.copy("Fixtures")]),
    ]
)
