// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Quitter",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "QuitterCore"),
        .executableTarget(name: "Quitter", dependencies: ["QuitterCore"]),
        .testTarget(name: "QuitterCoreTests", dependencies: ["QuitterCore"]),
    ]
)
