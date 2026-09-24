// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "PhoneAgentKit",
    platforms: [.iOS("26.4"), .macOS("26.4")],
    products: [.library(name: "PhoneAgentKit", targets: ["PhoneAgentKit"])],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1"),
    ],
    targets: [
        .target(name: "PhoneAgentKit", dependencies: [.product(name: "MCP", package: "swift-sdk")],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "HelloAgentCLI", dependencies: ["PhoneAgentKit"],
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "PhoneAgentKitTests", dependencies: ["PhoneAgentKit"],
                    swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
