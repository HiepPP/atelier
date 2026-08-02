import AppKit
import SwiftUI

/// Menu bar appearance panel. It repeats the Settings window controls and reads
/// the same two models, so neither surface owns a second copy of the state.
struct AtelierMenuBarView: View {
    @AppStorage(ResourceWatchdog.settingsKey) private var watchdogEnabled = true
    @Environment(AtelierZoomModel.self) private var zoom
    @Environment(AtelierAppearanceModel.self) private var appearance

    private static let panelWidth: CGFloat = 300

    var body: some View {
        @Bindable var zoom = zoom
        @Bindable var appearance = appearance

        VStack(alignment: .leading, spacing: 0) {
            AtelierMenuBarSection(title: "Text Size", isFirst: true) {
                textScaleRow(
                    title: "App",
                    scale: zoom.appTextScale,
                    onChange: zoom.setAppTextScale
                )
                textScaleRow(
                    title: "Editor",
                    scale: zoom.editorTextScale,
                    onChange: zoom.setEditorTextScale
                )
                textScaleRow(
                    title: "Terminal",
                    scale: zoom.terminalTextScale,
                    onChange: zoom.setTerminalTextScale
                )
            }

            AtelierMenuBarSection(title: "Zoom") {
                HStack(spacing: AtelierMetrics.spaceS) {
                    Text("Window zoom")
                        .atelierFont(size: AtelierTypography.label)
                    Spacer(minLength: AtelierMetrics.spaceS)
                    AtelierMenuBarStepper(
                        valueLabel: AtelierAppearancePolicy.percentLabel(zoom.manualScale),
                        decreaseLabel: "Zoom out",
                        increaseLabel: "Zoom in",
                        canDecrease: zoom.canZoomOut,
                        canIncrease: zoom.canZoomIn,
                        onDecrease: zoom.zoomOut,
                        onIncrease: zoom.zoomIn
                    )
                    Button("Reset") {
                        zoom.reset()
                    }
                    .buttonStyle(AtelierGhostButtonStyle())
                    .help("Reset Zoom")
                }
            }

            AtelierMenuBarSection(title: "Display") {
                Picker("Display sizing", selection: $zoom.sizingMode) {
                    ForEach(DisplaySizingMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .labelsHidden()
                .atelierPointerCursor()

                Toggle("Focus mode", isOn: focusModeBinding)
                    .toggleStyle(.switch)
                    .atelierFont(size: AtelierTypography.label)
                    .atelierPointerCursor()
            }

            AtelierMenuBarSection(title: "Code") {
                Toggle("Code ligatures", isOn: $appearance.codeLigaturesEnabled)
                    .toggleStyle(.switch)
                    .atelierFont(size: AtelierTypography.label)
                    .atelierPointerCursor()

                caption("The terminal updates now. The editor updates the next time the file opens.")
            }

            AtelierMenuBarSection(title: "Agent") {
                HStack(spacing: AtelierMetrics.spaceS) {
                    Text("Response text")
                        .atelierFont(size: AtelierTypography.label)
                    Spacer(minLength: AtelierMetrics.spaceS)
                    AtelierMenuBarStepper(
                        valueLabel: AtelierAppearancePolicy.percentLabel(
                            zoom.agentResponseTextScale
                        ),
                        decreaseLabel: "Decrease agent response text size",
                        increaseLabel: "Increase agent response text size",
                        canDecrease: AgentResponseTextSizePolicy.canDecrease(
                            zoom.agentResponseTextScale
                        ),
                        canIncrease: AgentResponseTextSizePolicy.canIncrease(
                            zoom.agentResponseTextScale
                        ),
                        onDecrease: {
                            zoom.setAgentResponseTextScale(
                                AgentResponseTextSizePolicy.decreased(zoom.agentResponseTextScale)
                            )
                        },
                        onIncrease: {
                            zoom.setAgentResponseTextScale(
                                AgentResponseTextSizePolicy.increased(zoom.agentResponseTextScale)
                            )
                        }
                    )
                }
            }

            AtelierMenuBarSection(title: "System") {
                Toggle("Resource safety gate", isOn: $watchdogEnabled)
                    .toggleStyle(.switch)
                    .atelierFont(size: AtelierTypography.label)
                    .atelierPointerCursor()

                caption("Quit Atelier automatically if it runs away (100% CPU for 5s, or 3 GB memory). Applies on next launch.")
            }

            HStack(spacing: AtelierMetrics.spaceS) {
                Button("Reset Appearance") {
                    zoom.resetAppearance()
                }
                .buttonStyle(AtelierGhostButtonStyle())
                .help("Reset zoom and every text size")

                Spacer(minLength: AtelierMetrics.spaceS)

                SettingsLink {
                    Text("Settings...")
                }
                .buttonStyle(AtelierGhostButtonStyle())
                .help("Open the Settings window")

                Button("Quit Atelier") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(AtelierGhostButtonStyle())
                .help("Quit Atelier")
            }
            .padding(.horizontal, AtelierMetrics.spaceL)
            .padding(.vertical, AtelierMetrics.spaceM)
        }
        .frame(width: Self.panelWidth)
        .background(AtelierMenuBarPanelSpaceBridge())
        .background(AtelierTheme.canvas)
        .tint(AtelierTheme.accent)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Atelier appearance")
    }

    private var focusModeBinding: Binding<Bool> {
        Binding(
            get: { zoom.isFocusMode },
            set: { _ in zoom.toggleFocusMode() }
        )
    }

    private func textScaleRow(
        title: String,
        scale: CGFloat,
        onChange: @escaping (CGFloat) -> Void
    ) -> some View {
        HStack(spacing: AtelierMetrics.spaceS) {
            Text(title)
                .atelierFont(size: AtelierTypography.label)
            Spacer(minLength: AtelierMetrics.spaceS)
            AtelierMenuBarStepper(
                valueLabel: AtelierAppearancePolicy.percentLabel(scale),
                decreaseLabel: "Decrease \(title.lowercased()) text size",
                increaseLabel: "Increase \(title.lowercased()) text size",
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
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .atelierFont(size: AtelierTypography.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Minus, value, plus. One click is one mutation, so a held drag cannot flood
/// the view tree the way a slider would.
private struct AtelierMenuBarStepper: View {
    let valueLabel: String
    let decreaseLabel: String
    let increaseLabel: String
    let canDecrease: Bool
    let canIncrease: Bool
    let onDecrease: () -> Void
    let onIncrease: () -> Void

    var body: some View {
        HStack(spacing: AtelierMetrics.spaceXS) {
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
        }
        .accessibilityElement(children: .contain)
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

/// Lets the panel open on the Space the user is looking at.
///
/// SwiftUI gives the `MenuBarExtra` panel a window that stays on the Space that
/// owns it. Clicking the item from another Space then opens the panel out of
/// sight: the runtime counters recorded a real show with `onActiveSpace` false
/// while the user saw nothing. This reaches the panel window through the view
/// that lives in it, so no window class name is guessed.
private struct AtelierMenuBarPanelSpaceBridge: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { PanelSpaceView() }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class PanelSpaceView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.collectionBehavior.insert(.moveToActiveSpace)
        }
    }
}

private struct AtelierMenuBarSection<Content: View>: View {
    let title: String
    var isFirst = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: AtelierMetrics.spaceS) {
            Text(title)
                .atelierFont(
                    size: AtelierTypography.label,
                    weight: .semibold,
                    design: .serif
                )
                .foregroundStyle(AtelierTheme.accent)

            content()
        }
        .padding(.horizontal, AtelierMetrics.spaceL)
        .padding(.vertical, AtelierMetrics.spaceM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            if !isFirst {
                Rectangle()
                    .fill(AtelierTheme.border)
                    .frame(height: AtelierTheme.strokeHairline)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
