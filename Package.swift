// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "glm-mcp",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
    ],
    targets: [
        .target(name: "GLMCore"),
        .target(name: "GLMBluetooth", dependencies: ["GLMCore"]),
        .target(
            name: "GLMServer",
            dependencies: [
                "GLMCore",
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .executableTarget(name: "GLMApp", dependencies: ["GLMCore", "GLMBluetooth", "GLMServer"]),
        .testTarget(name: "GLMCoreTests", dependencies: ["GLMCore"]),
        .testTarget(name: "GLMServerTests", dependencies: ["GLMServer", "GLMCore", .product(name: "MCP", package: "swift-sdk")]),
    ]
)
