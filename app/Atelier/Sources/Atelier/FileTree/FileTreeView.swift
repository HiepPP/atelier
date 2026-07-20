import SwiftUI

struct FileTreeView: View {
    let rootURL: URL
    let revision: Int
    let ignoredPaths: Set<String>
    let onTargetDirectoryChange: (URL) -> Void
    let onCreateItem: (FileTreeCreationKind, URL) -> Void
    let onRenameItem: (URL, String) -> Void
    let onMoveItemToTrash: (URL) -> Void
    let onAddItemToGitIgnore: (URL) -> Void
    let onPreview: (URL) -> Void
    let onOpen: (URL) -> Void

    var body: some View {
        FileTreeRepresentable(
            rootURL: rootURL,
            revision: revision,
            ignoredPaths: ignoredPaths,
            onTargetDirectoryChange: onTargetDirectoryChange,
            onCreateItem: onCreateItem,
            onRenameItem: onRenameItem,
            onMoveItemToTrash: onMoveItemToTrash,
            onAddItemToGitIgnore: onAddItemToGitIgnore,
            onPreview: onPreview,
            onOpen: onOpen
        )
    }
}
