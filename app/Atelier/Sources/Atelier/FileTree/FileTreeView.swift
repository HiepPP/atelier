import SwiftUI

struct FileTreeView: View {
    let rootURL: URL
    let revision: Int
    let onTargetDirectoryChange: (URL) -> Void
    let onCreateItem: (FileTreeCreationKind, URL) -> Void
    let onSelect: (URL) -> Void

    var body: some View {
        FileTreeRepresentable(
            rootURL: rootURL,
            revision: revision,
            onTargetDirectoryChange: onTargetDirectoryChange,
            onCreateItem: onCreateItem,
            onSelect: onSelect
        )
    }
}
