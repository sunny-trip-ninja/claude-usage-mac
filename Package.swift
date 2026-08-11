// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeUsage",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ClaudeUsageCore", targets: ["ClaudeUsageCore"]),
        .executable(name: "ClaudeUsage", targets: ["ClaudeUsage"]),
    ],
    targets: [
        .target(name: "ClaudeUsageCore"),
        .executableTarget(
            name: "ClaudeUsage",
            dependencies: ["ClaudeUsageCore"]
        ),
        .testTarget(
            name: "ClaudeUsageCoreTests",
            dependencies: ["ClaudeUsageCore"]
        ),
        .testTarget(
            name: "ClaudeUsageDocumentationTests",
            dependencies: ["ClaudeUsage"]
        ),
    ]
)
