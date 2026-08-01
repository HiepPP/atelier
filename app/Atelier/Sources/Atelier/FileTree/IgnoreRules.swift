import Foundation

nonisolated enum IgnoreRules {
    /// Hidden from every surface, Explorer included.
    private static let ignoredNames: Set<String> = [
        ".git",
        ".build",
        "node_modules",
        "DerivedData"
    ]

    /// Generated output and vendored dependencies. Explorer still lists these so
    /// Git-ignored rows stay visible at reduced opacity; the watcher and the
    /// workspace file index skip them.
    private static let generatedNames: Set<String> = [
        "dist",
        "build",
        "target",
        ".next",
        "Pods",
        ".venv",
        "out"
    ]

    private static let unindexedNames = ignoredNames.union(generatedNames)

    static func shouldIgnore(_ url: URL) -> Bool {
        ignoredNames.contains(url.lastPathComponent)
    }

    /// Quick Open and Search All Files candidates. Excludes hard build and
    /// dependency directories on top of the always-hidden names.
    static func shouldSkipIndexing(_ url: URL) -> Bool {
        unindexedNames.contains(url.lastPathComponent)
    }

    static func shouldIgnoreEventPath(_ path: String) -> Bool {
        path.split(separator: "/").contains { unindexedNames.contains(String($0)) }
    }
}
