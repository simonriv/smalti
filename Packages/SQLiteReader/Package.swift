// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SQLiteReader",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "SQLiteReader", targets: ["SQLiteReader"])
    ],
    targets: [
        .target(name: "SQLiteReader"),
        .testTarget(name: "SQLiteReaderTests", dependencies: ["SQLiteReader"]),
    ]
)
