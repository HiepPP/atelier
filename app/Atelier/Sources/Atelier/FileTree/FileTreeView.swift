import SwiftUI

struct FileTreeView: View {
    let rootURL: URL
    let revision: Int
    let onTargetDirectoryChange: (URL) -> Void
    let onCreateItem: (FileTreeCreationKind, URL) -> Void
    let onPreview: (URL) -> Void
    let onOpen: (URL) -> Void

    var body: some View {
        FileTreeRepresentable(
            rootURL: rootURL,
            revision: revision,
            onTargetDirectoryChange: onTargetDirectoryChange,
            onCreateItem: onCreateItem,
            onPreview: onPreview,
            onOpen: onOpen
        )
    }
}
