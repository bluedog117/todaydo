// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Todaydo",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "TodaydoCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "Todaydo",
            dependencies: ["TodaydoCore"]
        ),
        
        .executableTarget(
            name: "todaydo-selftest",
            dependencies: ["TodaydoCore"],
            path: "Sources/SelfTest"
        ),
    ]
)
