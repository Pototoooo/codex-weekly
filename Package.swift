// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexWeekly",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "CodexWeekly", targets: ["CodexWeekly"])
    ],
    targets: [
        .executableTarget(name: "CodexWeekly"),
        .testTarget(name: "CodexWeeklyTests", dependencies: ["CodexWeekly"])
    ]
)
