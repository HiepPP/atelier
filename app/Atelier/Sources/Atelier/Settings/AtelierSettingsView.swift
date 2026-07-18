import SwiftUI

struct AtelierSettingsView: View {
    @AppStorage(ResourceWatchdog.settingsKey) private var watchdogEnabled = true
    @Environment(AtelierZoomModel.self) private var zoom

    var body: some View {
        @Bindable var zoom = zoom
        VStack(spacing: 0) {
            AtelierPanelHeader(
                title: "Settings",
                subtitle: "Interface and system behavior",
                systemImage: "gearshape"
            )

            ScrollView {
                VStack(spacing: AtelierMetrics.spaceL) {
                    AtelierSettingsSection(
                        title: "Workspace",
                        systemImage: "macwindow"
                    ) {
                        AtelierShortcutRecorder()

                        Divider()

                        VStack(alignment: .leading, spacing: AtelierMetrics.spaceS) {
                            Text("Display sizing")
                                .atelierFont(size: AtelierTypography.label, weight: .medium)

                            Picker("Display sizing", selection: $zoom.sizingMode) {
                                ForEach(DisplaySizingMode.allCases, id: \.self) { mode in
                                    Text(mode.label).tag(mode)
                                }
                            }
                            .labelsHidden()

                            Text("Automatic scales text and UI to the display size: larger on desktop monitors, tighter on laptops. Pick a tier to force it. Zoom still stacks on top.")
                                .atelierFont(size: AtelierTypography.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    AtelierSettingsSection(
                        title: "Resource Safety",
                        systemImage: "gauge.with.dots.needle.33percent"
                    ) {
                        Toggle("Resource safety gate", isOn: $watchdogEnabled)
                            .toggleStyle(.switch)
                        Text("Quit Atelier automatically if it runs away (100% CPU for 5s, or 3 GB memory). Applies on next launch.")
                            .atelierFont(size: AtelierTypography.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(AtelierMetrics.spaceL)
            }
        }
        .background(AtelierTheme.canvas)
        .tint(AtelierTheme.accent)
        .frame(width: AtelierMetrics.settingsWidth)
        .frame(minHeight: AtelierMetrics.settingsMinHeight)
    }
}

private struct AtelierSettingsSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: AtelierMetrics.spaceM) {
            Label(title, systemImage: systemImage)
                .atelierFont(size: AtelierTypography.body, weight: .semibold)
                .foregroundStyle(AtelierTheme.accent)

            content()
        }
        .padding(AtelierMetrics.spaceL)
        .frame(maxWidth: .infinity, alignment: .leading)
        .atelierCard(radius: AtelierTheme.panelRadius)
        .accessibilityElement(children: .contain)
    }
}
