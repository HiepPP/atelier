import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    static let showAtelier = Self("showAtelier")
}

struct AtelierShortcutRecorder: View {
    var body: some View {
        KeyboardShortcuts.Recorder(
            "Show Atelier:",
            name: .showAtelier
        )
        .atelierPointerCursor()
    }
}
