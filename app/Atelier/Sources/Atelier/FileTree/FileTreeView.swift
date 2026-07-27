import SwiftUI

struct FileTreeView: View {
    let rootURL: URL
    let revision: Int
    let revealRequest: FileTreeRevealRequest?
    let ignoredPaths: Set<String>
    let onTargetDirectoryChange: (URL) -> Void
    let onCreateItem: (FileTreeCreationKind, URL) -> Void
    let onRenameItem: (URL, String) -> Void
    let onMoveItemToTrash: (URL) -> Void
    let onAddItemToGitIgnore: (URL) -> Void
    let onPasteRelativePath: (String) -> Bool
    let onPreview: (URL) -> Void
    let onOpen: (URL) -> Void

    var body: some View {
        FileTreeRepresentable(
            rootURL: rootURL,
            revision: revision,
            revealRequest: revealRequest,
            ignoredPaths: ignoredPaths,
            onTargetDirectoryChange: onTargetDirectoryChange,
            onCreateItem: onCreateItem,
            onRenameItem: onRenameItem,
            onMoveItemToTrash: onMoveItemToTrash,
            onAddItemToGitIgnore: onAddItemToGitIgnore,
            onPasteRelativePath: onPasteRelativePath,
            onPreview: onPreview,
            onOpen: onOpen
        )
    }
}
