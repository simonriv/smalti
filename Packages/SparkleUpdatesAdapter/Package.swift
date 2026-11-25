// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SparkleUpdatesAdapter",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "SparkleUpdatesAdapter", targets: ["SparkleUpdatesAdapter"])
    ],
    dependencies: [
        .package(path: "../SmaltiCore"),
        // F7.6: verified by the spike (ad hoc signature, EdDSA, DMG updates); bumped only on purpose.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
    ],
    targets: [
        .target(
            name: "SparkleUpdatesAdapter",
            dependencies: [
                .product(name: "SmaltiCore", package: "SmaltiCore"),
                .product(name: "Sparkle", package: "Sparkle"),
            ]),
        .testTarget(
            name: "SparkleUpdatesAdapterTests",
            dependencies: [
                "SparkleUpdatesAdapter",
                .product(name: "SmaltiCore", package: "SmaltiCore"),
                .product(name: "SmaltiCoreTestSupport", package: "SmaltiCore"),
            ]),
    ]
)
