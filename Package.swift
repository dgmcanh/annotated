// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Annotated",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Annotated", path: "Sources/Annotated")
    ]
)
