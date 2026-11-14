// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Battery",
    platforms: [.iOS(.v26)],
    products: [.library(name: "Battery", targets: ["Battery"])],
    targets: [
        .target(
            name: "Battery",
            exclude: ["Metadata.appintents"],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
            ]
        )
    ]
)
