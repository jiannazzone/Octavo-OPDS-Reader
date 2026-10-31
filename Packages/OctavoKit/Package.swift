// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "OctavoKit",
    platforms: [
        .iOS("27.1"),
        // macOS only so `swift test` runs without a simulator.
        .macOS("27.0"),
    ],
    products: [
        .library(name: "OctavoKit", targets: ["OctavoKit"]),
    ],
    targets: [
        .target(name: "OctavoKit"),
        .testTarget(name: "OctavoKitTests", dependencies: ["OctavoKit"]),
    ]
)
