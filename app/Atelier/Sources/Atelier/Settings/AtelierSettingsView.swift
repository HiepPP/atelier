import SwiftUI

struct AtelierSettingsView: View {
    @AppStorage(ResourceWatchdog.settingsKey) private var watchdogEnabled = true
    @Environment(AtelierZoomModel.self) private var zoom
    @Environment(AtelierAppearanceModel.self) private var appearance
    @State private var contentScrolled = false

    var body: some View {
        @Bindable var zoom = zoom
        @Bindable var appearance = appearance
        VStack(spacing: 0) {
            AtelierPanelHeader(
                title: "Settings",
                subtitle: "Interface and system behavior",
                systemImage: "gearshape",
                bottomDividerVisible: contentScrolled
            )

            ScrollView {
                VStack(spacing: 0) {
                    AtelierSettingsSection(
                        title: "Appearance",
                        systemImage: "textformat.size"
                    ) {
                        textScaleRow(
                            title: "App text size",
                            scale: zoom.appTextScale,
                            onChange: zoom.setAppTextScale
                        )

                        textScaleRow(
                            title: "Editor text size",
                            scale: zoom.editorTextScale,
                            onChange: zoom.setEditorTextScale
                        )

                        textScaleRow(
                            title: "Terminal text size",
                            scale: zoom.terminalTextScale,
                            onChange: zoom.setTerminalTextScale
                        )

                        AtelierSettingsStepperRow(
                            title: "Zoom",
                            valueLabel: AtelierAppearancePolicy.percentLabel(zoom.manualScale),
                            decreaseLabel: "Zoom out",
                            increaseLabel: "Zoom in",
                            canDecrease: zoom.canZoomOut,
                            canIncrease: zoom.canZoomIn,
                            onDecrease: zoom.zoomOut,
                            onIncrease: zoom.zoomIn,
                            resetAction: zoom.reset,
                            resetHelp: "Reset zoom to 100%"
                        )

                        Divider()

                        VStack(alignment: .leading, spacing: AtelierMetrics.spaceS) {
                            Toggle("Code ligatures", isOn: $appearance.codeLigaturesEnabled)
                                .toggleStyle(.switch)
                                .atelierPointerCursor()

                            caption("The terminal updates now. The editor updates the next time the file opens.")
                        }

                        VStack(alignment: .leading, spacing: AtelierMetrics.spaceS) {
                            Toggle("Menu bar item", isOn: $appearance.showsMenuBarExtra)
                                .toggleStyle(.switch)
                                .atelierPointerCursor()

                            caption("Hide the Atelier item in the menu bar. Your settings stay saved.")
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: AtelierMetrics.spaceS) {
                            Button("Reset appearance") {
                                zoom.resetAppearance()
                            }
                            .buttonStyle(AtelierGhostButtonStyle())
                            .help("Reset zoom and every text size")

                            caption("Return zoom and all text sizes to 100%.")
                        }
                    }

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
                            .atelierPointerCursor()

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
                            .atelierPointerCursor()
                        Text("Quit Atelier automatically if it runs away (100% CPU for 5s, or 3 GB memory). Applies on next launch.")
                            .atelierFont(size: AtelierTypography.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(AtelierMetrics.spaceL)
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y > 0.5
            } action: { _, scrolled in
                contentScrolled = scrolled
            }
        }
        .background(AtelierTheme.canvas)
        .tint(AtelierTheme.accent)
        .frame(width: AtelierMetrics.settingsWidth)
        .frame(minHeight: AtelierMetrics.settingsMinHeight)
    }

    private func textScaleRow(
        title: String,
        scale: CGFloat,
        onChange: @escaping (CGFloat) -> Void
    ) -> some View {
        AtelierSettingsStepperRow(
            title: title,
            valueLabel: AtelierAppearancePolicy.percentLabel(scale),
            decreaseLabel: "Decrease \(title.lowercased())",
            increaseLabel: "Increase \(title.lowercased())",
            canDecrease: scale > AtelierAppearancePolicy.minimumTextScale,
            canIncrease: scale < AtelierAppearancePolicy.maximumTextScale,
            onDecrease: {
                onChange(
                    AtelierAppearancePolicy.clampedTextScale(
                        scale - AtelierAppearancePolicy.textScaleStep
                    )
                )
            },
            onIncrease: {
                onChange(
                    AtelierAppearancePolicy.clampedTextScale(
                        scale + AtelierAppearancePolicy.textScaleStep
                    )
                )
            }
        )
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .atelierFont(size: AtelierTypography.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Title, minus, percent, plus, with an optional reset. One shape for every
/// scale row, and one mutation per click so a held press cannot flood the tree.
private struct AtelierSettingsStepperRow: View {
    let title: String
    let valueLabel: String
    let decreaseLabel: String
    let increaseLabel: String
    let canDecrease: Bool
    let canIncrease: Bool
    let onDecrease: () -> Void
    let onIncrease: () -> Void
    var resetAction: (() -> Void)?
    var resetHelp = "Reset"

    var body: some View {
        HStack(spacing: AtelierMetrics.spaceS) {
            Text(title)
                .atelierFont(size: AtelierTypography.label)

            Spacer(minLength: AtelierMetrics.spaceS)

            stepButton(
                systemImage: "minus",
                label: decreaseLabel,
                isEnabled: canDecrease,
                action: onDecrease
            )

            Text(valueLabel)
                .atelierFont(size: AtelierTypography.caption, design: .monospaced)
                .foregroundStyle(.secondary)
                .frame(minWidth: AtelierMetrics.zoomLabelMinWidth, alignment: .trailing)
                .accessibilityHidden(true)

            stepButton(
                systemImage: "plus",
                label: increaseLabel,
                isEnabled: canIncrease,
                action: onIncrease
            )

            if let resetAction {
                Button("Reset", action: resetAction)
                    .buttonStyle(AtelierGhostButtonStyle())
                    .help(resetHelp)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityValue(valueLabel)
    }

    private func stepButton(
        systemImage: String,
        label: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: AtelierMetrics.regularIconSize)
        }
        .buttonStyle(AtelierGhostButtonStyle())
        .disabled(!isEnabled)
        .accessibilityLabel(label)
        .help(label)
    }
}

private struct AtelierSettingsSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: AtelierMetrics.spaceM) {
            Label(title, systemImage: systemImage)
                .atelierFont(
                    size: AtelierTypography.title,
                    weight: .semibold,
                    design: .serif
                )
                .foregroundStyle(AtelierTheme.accent)

            content()
        }
        .padding(.horizontal, AtelierMetrics.spaceL)
        .padding(.vertical, AtelierMetrics.spaceXL)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AtelierTheme.border)
                .frame(height: AtelierTheme.strokeHairline)
        }
        .accessibilityElement(children: .contain)
    }
}
