import SwiftUI

struct FileTreeView: View {
    let rootURL: URL
    let revision: Int
    let onSelect: (URL) -> Void

    var body: some View {
        FileTreeRepresentable(
            rootURL: rootURL,
            revision: revision,
            onSelect: onSelect
        )
    }
}
