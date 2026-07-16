// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Atelier",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", exact: "1.14.0"),
        .package(url: "https://github.com/siteline/swiftui-introspect", exact: "26.0.1"),
        .package(url: "https://github.com/appstefan/HighlightSwift.git", exact: "1.1.0"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", exact: "3.0.1"),
        .package(url: "https://github.com/EmergeTools/Pow", exact: "1.0.5"),
        .package(path: "../../Vendor/Luminare")
    ],
    targets: [
        .executableTarget(
            name: "Atelier",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                .product(name: "SwiftUIIntrospect", package: "swiftui-introspect"),
                "HighlightSwift",
                "KeyboardShortcuts",
                "Pow",
                "Luminare"
            ]
        )
    ]
)
