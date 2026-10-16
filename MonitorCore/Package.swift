// swift-tools-version:5.9

import PackageDescription

let package = Package(
        name: "Monitor",
        platforms: [.macOS(.v13)],
        products: [
            .library(name: "Monitor", targets: ["Monitor"]),
            .library(name: "Utils", targets: ["Utils"]),
        ],
        targets: [
            .target(name: "Monitor"),
            .target(name: "Utils"),
            .testTarget(name: "MonitorTests", dependencies: ["Monitor"]),
            .testTarget(name: "UtilsTests", dependencies: ["Utils"]),
        ]
)
