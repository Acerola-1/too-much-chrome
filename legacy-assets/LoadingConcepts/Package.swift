// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LoadingConcepts",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "LoadingConcepts",
            path: "Sources/LoadingConcepts"
        )
    ]
)
