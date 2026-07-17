import SwiftUI

struct AtelierSettingsView: View {
    @AppStorage(ResourceWatchdog.settingsKey) private var watchdogEnabled = true

    var body: some View {
        Form {
            AtelierShortcutRecorder()

            Section {
                Toggle("Resource safety gate", isOn: $watchdogEnabled)
                Text("Quit Atelier automatically if it runs away (100% CPU for 5s, or 3 GB memory). Applies on next launch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 420)
    }
}
