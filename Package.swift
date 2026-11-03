// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "YariAltTab",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "YariAltTab",
            path: "Sources/YariAltTab"
        )
    ]
)
