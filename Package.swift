// swift-tools-version: 5.9
import PackageDescription

/// `DrawnTimerEngine` is macOS-testable from the CLI. **`DrawnActivityModels`** holds
/// `TimerActivityAttributes` so the **app + widget extension** share one module (ActivityKit).
let package = Package(
    name: "DrawnPackages",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DrawnTimerEngine", targets: ["DrawnTimerEngine"]),
        .library(name: "DrawnActivityModels", targets: ["DrawnActivityModels"]),
    ],
    targets: [
        .target(
            name: "DrawnActivityModels",
            dependencies: [],
            linkerSettings: [
                .linkedFramework("ActivityKit", .when(platforms: [.iOS]))
            ]
        ),
        .target(
            name: "DrawnTimerEngine",
            dependencies: []
        ),
        .testTarget(
            name: "DrawnTimerEngineTests",
            dependencies: ["DrawnTimerEngine"]
        ),
    ]
)
