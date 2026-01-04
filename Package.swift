// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SwiftGuidelinesMCP",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.10.0")
    ],
    targets: [
        .executableTarget(
            name: "SwiftGuidelinesMCP",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk")
            ]
        )
    ]
)

