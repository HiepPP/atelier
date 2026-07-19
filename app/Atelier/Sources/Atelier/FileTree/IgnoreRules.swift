import Foundation

nonisolated enum IgnoreRules {
    private static let ignoredNames: Set<String> = [
        ".git",
        ".build",
        "node_modules",
        "DerivedData"
    ]

    static func shouldIgnore(_ url: URL) -> Bool {
        ignoredNames.contains(url.lastPathComponent)
    }

    static func shouldIgnoreEventPath(_ path: String) -> Bool {
        path.split(separator: "/").contains { ignoredNames.contains(String($0)) }
    }
}
