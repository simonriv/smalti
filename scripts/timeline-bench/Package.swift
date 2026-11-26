// swift-tools-version: 6.2
import PackageDescription

// F9 C5/C7/C8 measurements (scripts/measure-timeline.sh): the timeline's adapters over a Claude home, read-only.
// Not part of the app.
let package = Package(
    name: "TimelineBench",
    platforms: [.macOS("27.0")],
    dependencies: [
        .package(path: "../../Packages/SmaltiCore"),
        .package(path: "../../Packages/ClaudeHarnessAdapter"),
    ],
    targets: [
        .executableTarget(
            name: "TimelineBench",
            dependencies: [
                .product(name: "SmaltiCore", package: "SmaltiCore"),
                .product(name: "ClaudeHarnessAdapter", package: "ClaudeHarnessAdapter"),
            ])
    ]
)
