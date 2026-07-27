// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Atelier",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", exact: "1.15.0"),
        .package(url: "https://github.com/appstefan/HighlightSwift.git", exact: "1.1.0"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", exact: "3.0.1"),
        .package(url: "https://github.com/EmergeTools/Pow", exact: "1.0.5"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1"),
        .package(path: "../../Vendor/Luminare")
    ],
    targets: [
        .executableTarget(
            name: "Atelier",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                "HighlightSwift",
                "KeyboardShortcuts",
                "Pow",
                .product(name: "MCP", package: "swift-sdk"),
                "Luminare"
            ],
            resources: [
                .copy("Resources/Mermaid"),
                .copy("Resources/MaterialIconTheme")
            ],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault")
            ]
        ),
        .testTarget(
            name: "AtelierTests",
            dependencies: ["Atelier"],
            resources: [
                .copy("Fixtures")
            ],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
