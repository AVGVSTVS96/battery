// swift-tools-version: 6.2
import PackageDescription

let settings: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
]

let package = Package(
    name: "Battery",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "Battery", targets: ["Battery"]),
        .library(name: "ScreenTime", targets: ["ScreenTime"]),
    ],
    targets: [
        .target(name: "Design", swiftSettings: settings),
        .target(name: "Battery", dependencies: ["Design"], exclude: ["Metadata.appintents"], swiftSettings: settings),
        .target(name: "ScreenTime", dependencies: ["Design"]),
    ]
)
