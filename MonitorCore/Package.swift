// swift-tools-version:5.9

import PackageDescription

let package = Package(
        name: "Monitor",
        platforms: [.macOS(.v13)],
        products: [
            .library(name: "Monitor", targets: ["Monitor"]),
            .library(name: "Utils", targets: ["Utils"]),
        ],
        dependencies: [
            // Dependencies declare other packages that this package depends on.
            // .package(url: /* package url */, from: "1.0.0"),
        ],
        targets: [
            .target(name: "Monitor"),
            .target(name: "Utils"),
        ]
)
