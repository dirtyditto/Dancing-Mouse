// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DancingMouse",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DancingMouse",
            path: "Sources/DancingMouse",
            exclude: ["Resources"]
        )
    ]
)
