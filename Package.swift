// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TunnelhuntTray",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "TunnelhuntTray", targets: ["TunnelhuntTray"])
    ],
    targets: [
        .executableTarget(
            name: "TunnelhuntTray",
            dependencies: [],
            path: "Sources"
        )
    ]
)
