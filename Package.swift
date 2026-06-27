// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Insonia",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Insonia",
            path: "Sources/Insonia"
        )
    ]
)
