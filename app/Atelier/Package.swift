// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Atelier",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", exact: "1.14.0"),
        .package(url: "https://github.com/siteline/swiftui-introspect", exact: "26.0.1")
    ],
    targets: [
        .executableTarget(
            name: "Atelier",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                .product(name: "SwiftUIIntrospect", package: "swiftui-introspect")
            ]
        )
    ]
)
