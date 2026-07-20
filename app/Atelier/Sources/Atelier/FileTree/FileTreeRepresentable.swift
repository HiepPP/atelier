import AppKit
import SwiftUI

struct FileTreeRepresentable: NSViewRepresentable {
    @Environment(\.atelierZoomScale) private var scale
    @Environment(\.displayScale) private var displayScale

    let rootURL: URL
    let revision: Int
    let ignoredPaths: Set<String>
    let onTargetDirectoryChange: (URL) -> Void
    let onCreateItem: (FileTreeCreationKind, URL) -> Void
    let onRenameItem: (URL, String) -> Void
    let onMoveItemToTrash: (URL) -> Void
    let onAddItemToGitIgnore: (URL) -> Void
    let onPasteRelativePath: (String) -> Bool
    let onPreview: (URL) -> Void
    let onOpen: (URL) -> Void

    func makeCoordinator() -> FileTreeController {
        FileTreeController(
            rootURL: rootURL,
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

    func makeNSView(context: Context) -> NSScrollView {
        context.coordinator.makeView(scale: scale, displayScale: displayScale)
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.update(
            rootURL: rootURL,
            revision: revision,
            ignoredPaths: ignoredPaths,
            scale: scale,
            displayScale: displayScale,
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

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: FileTreeController) {
        coordinator.stop()
    }
}
