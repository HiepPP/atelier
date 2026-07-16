import SwiftUI

struct AtelierSettingsView: View {
    var body: some View {
        Form {
            AtelierShortcutRecorder()
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 420)
    }
}
