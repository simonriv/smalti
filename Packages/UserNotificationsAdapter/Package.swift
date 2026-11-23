// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "UserNotificationsAdapter",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "UserNotificationsAdapter", targets: ["UserNotificationsAdapter"])
    ],
    dependencies: [
        .package(path: "../SmaltiCore")
    ],
    targets: [
        .target(
            name: "UserNotificationsAdapter",
            dependencies: [.product(name: "SmaltiCore", package: "SmaltiCore")]),
        .testTarget(
            name: "UserNotificationsAdapterTests",
            dependencies: [
                "UserNotificationsAdapter",
                .product(name: "SmaltiCore", package: "SmaltiCore"),
                .product(name: "SmaltiCoreTestSupport", package: "SmaltiCore"),
            ]),
    ]
)
