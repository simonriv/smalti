// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "IPCAdapter",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "SmaltiIPCProtocol", targets: ["SmaltiIPCProtocol"]),
        .library(name: "IPCAdapter", targets: ["IPCAdapter"]),
        .executable(name: "smalti", targets: ["smalti"]),
    ],
    dependencies: [
        .package(path: "../SmaltiCore"),
        .package(path: "../ImageIOAdapter"),
    ],
    targets: [
        // Wire format only: no SmaltiCore, so the CLI starts fast inside a hook.
        .target(name: "SmaltiIPCProtocol"),
        .target(
            name: "IPCAdapter",
            dependencies: ["SmaltiIPCProtocol", .product(name: "SmaltiCore", package: "SmaltiCore")]),
        // F5.5: `img` needs the domain and ImageIO; linking them costs `event` ~0.2 ms (plan T1).
        .executableTarget(
            name: "smalti",
            dependencies: [
                "SmaltiIPCProtocol", .product(name: "SmaltiCore", package: "SmaltiCore"),
                .product(name: "ImageIOAdapter", package: "ImageIOAdapter"),
            ]),
        .testTarget(name: "SmaltiIPCProtocolTests", dependencies: ["SmaltiIPCProtocol"]),
        .testTarget(
            name: "IPCAdapterTests",
            dependencies: [
                "IPCAdapter", "SmaltiIPCProtocol", .product(name: "SmaltiCore", package: "SmaltiCore"),
                .product(name: "SmaltiCoreTestSupport", package: "SmaltiCore"),
            ]),
        .testTarget(
            name: "SmaltiCLITests",
            dependencies: [
                "smalti", "SmaltiIPCProtocol", .product(name: "SmaltiCore", package: "SmaltiCore"),
                .product(name: "SmaltiCoreTestSupport", package: "SmaltiCore"),
            ]),
    ]
)
