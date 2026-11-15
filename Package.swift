// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Flick",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Flick", path: "Sources/Flick")
    ]
)
