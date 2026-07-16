// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AtelierLibraryCompatibility",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/SwiftUIX/SwiftUIX", exact: "0.3.1"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", exact: "3.0.1"),
        .package(url: "https://github.com/EmergeTools/Pow", exact: "1.0.5"),
        .package(url: "https://github.com/siteline/swiftui-introspect", exact: "26.0.1"),
        .package(path: "../../Vendor/Luminare")
    ],
    targets: [
        .executableTarget(
            name: "UILibrariesSpike",
            dependencies: [
                "SwiftUIX",
                "KeyboardShortcuts",
                "Pow",
                .product(name: "SwiftUIIntrospect", package: "swiftui-introspect"),
                "Luminare"
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
