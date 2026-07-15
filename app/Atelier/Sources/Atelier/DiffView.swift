import SwiftUI

struct DiffView: View {
    let text: String

    var body: some View {
        FileViewer(content: .text(text.isEmpty ? "No diff output." : text))
    }
}
