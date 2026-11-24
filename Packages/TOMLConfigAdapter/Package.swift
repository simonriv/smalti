// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TOMLConfigAdapter",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "TOMLConfigAdapter", targets: ["TOMLConfigAdapter"])
    ],
    dependencies: [
        .package(path: "../SmaltiCore"),
        // Pure Swift, no C++ interop. Pinned exactly; bump in its own PR.
        .package(url: "https://github.com/dduan/TOMLDecoder", exact: "0.4.5"),
    ],
    targets: [
        .target(
            name: "TOMLConfigAdapter",
            dependencies: [
                .product(name: "SmaltiCore", package: "SmaltiCore"),
                .product(name: "TOMLDecoder", package: "TOMLDecoder"),
            ]),
        .testTarget(
            name: "TOMLConfigAdapterTests",
            dependencies: [
                "TOMLConfigAdapter",
                .product(name: "SmaltiCore", package: "SmaltiCore"),
                .product(name: "SmaltiCoreTestSupport", package: "SmaltiCore"),
                .product(name: "TOMLDecoder", package: "TOMLDecoder"),
            ],
            exclude: ["Fixtures"]),
    ]
)
