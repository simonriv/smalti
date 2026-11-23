// swift-tools-version: 6.2
import PackageDescription

// F4 C1 benchmark (scripts/measure-input.sh): suggestions end to end, from zsh's `line` to the ghost text painted,
// with the real input server, session and adapters and a real zsh. Not part of the app.
let package = Package(
    name: "InputBench",
    platforms: [.macOS("27.0")],
    dependencies: [
        .package(path: "../../Packages/SmaltiCore"),
        .package(path: "../../Packages/IPCAdapter"),
        .package(path: "../../Packages/FileSessionAdapter"),
        .package(path: "../../Packages/FigCompletionAdapter"),
        .package(path: "../../Packages/ProjectContextAdapter"),
        .package(path: "../../Packages/GhosttyAdapter"),
    ],
    targets: [
        .executableTarget(
            name: "InputBench",
            dependencies: [
                .product(name: "SmaltiCore", package: "SmaltiCore"),
                .product(name: "IPCAdapter", package: "IPCAdapter"),
                .product(name: "FileSessionAdapter", package: "FileSessionAdapter"),
                .product(name: "FigCompletionAdapter", package: "FigCompletionAdapter"),
                .product(name: "ProjectContextAdapter", package: "ProjectContextAdapter"),
                .product(name: "GhosttyAdapter", package: "GhosttyAdapter"),
            ])
    ]
)
