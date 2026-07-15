// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SwiftTermSpike",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.14.0")
    ],
    targets: [
        .executableTarget(
            name: "SwiftTermSpike",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ]
        )
    ]
)
