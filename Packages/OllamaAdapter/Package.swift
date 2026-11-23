// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OllamaAdapter",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "OllamaAdapter", targets: ["OllamaAdapter"])
    ],
    dependencies: [
        .package(path: "../SmaltiCore")
    ],
    targets: [
        .target(
            name: "OllamaAdapter",
            dependencies: [.product(name: "SmaltiCore", package: "SmaltiCore")]),
        .testTarget(
            name: "OllamaAdapterTests",
            dependencies: [
                "OllamaAdapter",
                .product(name: "SmaltiCore", package: "SmaltiCore"),
                .product(name: "SmaltiCoreTestSupport", package: "SmaltiCore"),
            ]),
    ]
)
