// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "LisdoCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "LisdoCore",
            targets: ["LisdoCore"]
        )
    ],
    targets: [
        .target(
            name: "LisdoCore"
        ),
        .testTarget(
            name: "LisdoCoreTests",
            dependencies: ["LisdoCore"]
        )
    ]
)
