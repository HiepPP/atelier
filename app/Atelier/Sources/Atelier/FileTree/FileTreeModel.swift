import Foundation

nonisolated struct FileTreeEntry: Equatable, Sendable {
    let url: URL
    let isDirectory: Bool
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

@MainActor
final class FileTreeNode {
    let url: URL
    let isDirectory: Bool
    private(set) var children: [FileTreeNode]?
    private(set) var isLoading = false

    var name: String { url.lastPathComponent }

    init(url: URL, isDirectory: Bool) {
        self.url = url
        self.isDirectory = isDirectory
    }

    func beginLoading() -> Bool {
        guard isDirectory, !isLoading else { return false }
        isLoading = true
        return true
    }

    func apply(_ entries: [FileTreeEntry]) {
        let existing = Dictionary(uniqueKeysWithValues: (children ?? []).map { ($0.url, $0) })
        children = entries.map { entry in
            if let node = existing[entry.url], node.isDirectory == entry.isDirectory {
                return node
            }
            return FileTreeNode(url: entry.url, isDirectory: entry.isDirectory)
        }
        isLoading = false
    }

    func failLoading() {
        children = children ?? []
        isLoading = false
    }
}
