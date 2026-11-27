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
        ),
        .executable(
            name: "MacFileExplorerMusicDecoy",
            targets: ["MacFileExplorerMusicDecoy"]
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
        .executableTarget(
            name: "MacFileExplorerMusicDecoy",
            path: "Sources/MacFileExplorerMusicDecoy"
        ),
        .testTarget(
            name: "MacFileExplorerTests",
            dependencies: ["MacFileExplorer"],
            path: "Tests/MacFileExplorerTests"
        ),
        .testTarget(
            name: "MacFileExplorerValidationTests",
            dependencies: ["MacFileExplorer"],
            path: "Tests/MacFileExplorerValidationTests"
        )
    ]
)
