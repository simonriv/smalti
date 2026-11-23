// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FigCompletionAdapter",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "FigCompletionAdapter", targets: ["FigCompletionAdapter"])
    ],
    dependencies: [
        .package(path: "../SmaltiCore")
    ],
    targets: [
        .target(
            name: "FigCompletionAdapter",
            dependencies: [.product(name: "SmaltiCore", package: "SmaltiCore")],
            resources: [.copy("Specs"), .copy("LICENSE-fig.txt")]),
        .testTarget(
            name: "FigCompletionAdapterTests",
            dependencies: [
                "FigCompletionAdapter",
                .product(name: "SmaltiCore", package: "SmaltiCore"),
                .product(name: "SmaltiCoreTestSupport", package: "SmaltiCore"),
            ]),
    ]
)
