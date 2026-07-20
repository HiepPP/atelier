import Foundation

nonisolated struct FileTreeEntry: Equatable, Sendable {
    let url: URL
    let isDirectory: Bool
    let isSymbolicLink: Bool
    let symbolicLinkTargetIsDirectory: Bool
}

enum FileTreeCreationKind: Equatable, Sendable {
    case file
    case folder

    var title: String { self == .file ? "New File" : "New Folder" }
    var placeholder: String { self == .file ? "File name" : "Folder name" }
    var systemImage: String { self == .file ? "doc" : "folder.fill" }
}

struct FileTreeCreationRequest: Equatable, Identifiable {
    let id = UUID()
    let kind: FileTreeCreationKind
    let parentURL: URL
}

nonisolated enum FileTreePathPolicy {
    static func relativePath(of url: URL, within rootURL: URL) -> String? {
        let rootComponents = rootURL.standardizedFileURL.pathComponents
        let itemComponents = url.standardizedFileURL.pathComponents
        guard itemComponents.count > rootComponents.count,
              itemComponents.starts(with: rootComponents) else { return nil }
        return itemComponents.dropFirst(rootComponents.count).joined(separator: "/")
    }

    static func terminalReference(for relativePath: String) -> String {
        "@\(relativePath) "
    }

    static func contains(_ candidateURL: URL, within rootURL: URL) -> Bool {
        let candidatePath = candidateURL.standardizedFileURL.path
        let rootPath = rootURL.standardizedFileURL.path
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }

    static func replacingRoot(
        of candidateURL: URL,
        from sourceURL: URL,
        to destinationURL: URL
    ) -> URL? {
        let sourcePath = sourceURL.standardizedFileURL.path
        let candidatePath = candidateURL.standardizedFileURL.path
        guard candidatePath == sourcePath || candidatePath.hasPrefix(sourcePath + "/") else {
            return nil
        }
        let suffix = String(candidatePath.dropFirst(sourcePath.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !suffix.isEmpty else { return destinationURL.standardizedFileURL }
        return destinationURL.appendingPathComponent(suffix).standardizedFileURL
    }
}

nonisolated enum FileTreeGitIgnorePresentation {
    static func isIgnored(
        _ url: URL,
        rootURL: URL,
        ignoredPaths: Set<String>
    ) -> Bool {
        guard let relativePath = FileTreePathPolicy.relativePath(of: url, within: rootURL) else {
            return false
        }
        return ignoredPaths.contains { ignoredPath in
            let normalized = ignoredPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return relativePath == normalized || relativePath.hasPrefix(normalized + "/")
        }
    }
}

nonisolated enum GitIgnorePattern {
    static func pattern(relativePath: String, isDirectory: Bool) -> String {
        let escaped = relativePath.reduce(into: "") { result, character in
            if "\\*?[]".contains(character) { result.append("\\") }
            result.append(character)
        }
        return "/\(escaped)\(isDirectory ? "/" : "")"
    }
}

@MainActor
final class FileTreeNode {
    let url: URL
    let isDirectory: Bool
    let isSymbolicLink: Bool
    let symbolicLinkTargetIsDirectory: Bool
    private(set) var children: [FileTreeNode]?
    private(set) var isLoading = false

    var name: String { url.lastPathComponent }

    init(
        url: URL,
        isDirectory: Bool,
        isSymbolicLink: Bool = false,
        symbolicLinkTargetIsDirectory: Bool = false
    ) {
        self.url = url
        self.isDirectory = isDirectory
        self.isSymbolicLink = isSymbolicLink
        self.symbolicLinkTargetIsDirectory = symbolicLinkTargetIsDirectory
    }

    func beginLoading() -> Bool {
        guard isDirectory, !isLoading else { return false }
        isLoading = true
        return true
    }

    /// Applies a fresh directory listing and reports whether the visible
    /// children actually changed, so callers can skip outline reloads for
    /// no-op refreshes.
    func apply(_ entries: [FileTreeEntry]) -> Bool {
        let existing = Dictionary(uniqueKeysWithValues: (children ?? []).map { ($0.url, $0) })
        let updated = entries.map { entry in
            if let node = existing[entry.url],
               node.isDirectory == entry.isDirectory,
               node.isSymbolicLink == entry.isSymbolicLink,
               node.symbolicLinkTargetIsDirectory == entry.symbolicLinkTargetIsDirectory {
                return node
            }
            return FileTreeNode(
                url: entry.url,
                isDirectory: entry.isDirectory,
                isSymbolicLink: entry.isSymbolicLink,
                symbolicLinkTargetIsDirectory: entry.symbolicLinkTargetIsDirectory
            )
        }
        let changed: Bool
        if let current = children {
            changed = current.count != updated.count
                || zip(current, updated).contains { $0 !== $1 }
        } else {
            changed = true
        }
        children = updated
        isLoading = false
        return changed
    }

    func failLoading() {
        children = children ?? []
        isLoading = false
    }
}
