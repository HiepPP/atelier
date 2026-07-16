// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "LuminareSpike",
    platforms: [
        .macOS(.v26)
    ],
    dependencies: [
        .package(path: "../../Vendor/Luminare"),
        .package(url: "https://github.com/siteline/swiftui-introspect", exact: "26.0.1")
    ],
    targets: [
        .executableTarget(
            name: "LuminareSpike",
            dependencies: [
                "Luminare",
                .product(name: "SwiftUIIntrospect", package: "swiftui-introspect")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
