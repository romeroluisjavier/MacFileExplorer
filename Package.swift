// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacFileExplorer",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "MacFileExplorer",
            targets: ["MacFileExplorer"]
        )
    ],
    targets: [
        .executableTarget(
            name: "MacFileExplorer",
            path: "Sources/MacFileExplorer",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "MacFileExplorerTests",
            dependencies: ["MacFileExplorer"],
            path: "Tests/MacFileExplorerTests"
        )
    ]
)
