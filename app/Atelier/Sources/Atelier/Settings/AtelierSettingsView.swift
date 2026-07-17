import SwiftUI

struct AtelierSettingsView: View {
    @AppStorage(ResourceWatchdog.settingsKey) private var watchdogEnabled = true
    @Environment(AtelierZoomModel.self) private var zoom

    var body: some View {
        @Bindable var zoom = zoom
        Form {
            AtelierShortcutRecorder()

            Section {
                Picker("Display sizing", selection: $zoom.sizingMode) {
                    ForEach(DisplaySizingMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                Text("Automatic scales text and UI to the display size: larger on desktop monitors, tighter on laptops. Pick a tier to force it. Zoom still stacks on top.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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
