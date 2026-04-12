// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RetinaScaler",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "RetinaScaler",
            path: "Sources",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
