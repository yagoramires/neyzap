// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "NeyZap",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "NeyZap",
            path: "Sources/NeyZap",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedFramework("Carbon")]
        )
    ]
)
