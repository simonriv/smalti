// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "GhosttyAdapter",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "GhosttyAdapter", targets: ["GhosttyAdapter"])
    ],
    dependencies: [
        .package(path: "../SmaltiCore")
    ],
    targets: [
        // Built by scripts/build-ghostty.sh from the pinned vendor/ghostty commit (not versioned).
        .binaryTarget(name: "GhosttyKit", path: "Frameworks/GhosttyKit.xcframework"),
        .target(
            name: "GhosttyAdapter",
            dependencies: ["SmaltiCore", "GhosttyKit"],
            exclude: ["ThirdParty/LICENSE-ghostty.txt"],
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreText"),
                .linkedFramework("IOSurface"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("QuartzCore"),
            ]),
        .testTarget(
            name: "GhosttyAdapterTests",
            dependencies: [
                "GhosttyAdapter", "GhosttyKit", "SmaltiCore",
                .product(name: "SmaltiCoreTestSupport", package: "SmaltiCore"),
            ],
            resources: [.copy("Fixtures")]),
    ]
)
