import AppKit
import SwiftUI

/// Container for the context-aware Gemma sidecar. One-feed, one-input layout:
/// a compact header (icon, title, status, intent chip, gear), a single scrolling
/// feed where every output renders as a card (journal milestones, Guardian
/// diagnosis, Whisper advisory, intent drift, chat turns, tool activity, Claude
/// handoff), and one input zone (quick-action chips above one prompt field).
/// Background features render nothing while idle and never reserve fixed space.
struct GemmaSidecarView: View {
    @Bindable var model: GemmaSidecarModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @FocusState private var isPromptFocused: Bool
    @State private var isIntentPopoverPresented = false
    @State private var isSettingsPopoverPresented = false
    @AppStorage(TerminalGuardianModel.settingsKey) private var guardianEnabled = true
    @AppStorage(SessionJournalModel.settingsKey) private var journalEnabled = true

    var body: some View {
        Group {
            if let context = model.context {
                content(for: context)
            } else {
                AtelierEmptyState(
                    systemImage: "sparkles",
                    title: "Gemma Sidecar",
                    message: "Open a tab to get context-aware, read-only help."
                )
            }
        }
        .background(AtelierTheme.panel)
        .accessibilityLabel("Gemma sidecar assistant")
    }

    private func content(for context: GemmaSidecarTabContext) -> some View {
        VStack(spacing: 0) {
            header(context)
            feed
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            inputZone(for: context)
        }
        .onAppear { isPromptFocused = true }
    }

    // MARK: - Header

    private func header(_ context: GemmaSidecarTabContext) -> some View {
        HStack(alignment: .center, spacing: AtelierMetrics.spaceM) {
            ZStack {
                RoundedRectangle(cornerRadius: AtelierTheme.rowRadius, style: .continuous)
                    .fill(AtelierTheme.accent.opacity(contrast == .increased ? 0.18 : 0.10))
                Image(systemName: context.systemImage)
                    .atelierFont(size: AtelierTypography.uiSize, weight: .medium)
                    .foregroundStyle(AtelierTheme.accent)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(context.title)
                    .atelierFont(size: AtelierTypography.uiSize, weight: .semibold)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)
                HStack(spacing: AtelierMetrics.spaceXS) {
                    if model.interactive.isRunning {
                        Image(systemName: "circle.fill")
                            .atelierFont(size: 7)
                            .foregroundStyle(AtelierTheme.accent)
                            .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
                            .accessibilityHidden(true)
                    }
                    Text("\(context.kind.rawValue) - \(context.status)")
                        .atelierFont(size: AtelierTypography.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            intentChip
            settingsButton
        }
        .padding(.horizontal, AtelierMetrics.spaceM)
        .frame(minHeight: AtelierMetrics.panelHeaderHeight)
        .padding(.vertical, AtelierMetrics.spaceXS)
        .background(AtelierTheme.chrome)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AtelierTheme.border)
                .frame(height: AtelierTheme.strokeHairline)
        }
    }

    private var intentChip: some View {
        Button {
            isIntentPopoverPresented = true
        } label: {
            HStack(spacing: AtelierMetrics.spaceXS) {
                Image(systemName: "target")
                    .atelierFont(size: AtelierTypography.caption, weight: .medium)
                if hasIntent {
                    Text(model.intentGuard.intent)
                        .atelierFont(size: AtelierTypography.caption)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 120, alignment: .leading)
                }
            }
        }
        .buttonStyle(AtelierGhostButtonStyle(tint: hasIntent ? AtelierTheme.accent : .secondary))
        .popover(isPresented: $isIntentPopoverPresented, arrowEdge: .bottom) {
            intentPopover
        }
        .accessibilityLabel(hasIntent ? "Intent: \(model.intentGuard.intent)" : "Set intent")
        .help("State your intent for this session; Gemma flags drifting changes")
    }

    private var hasIntent: Bool {
        !model.intentGuard.intent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var intentPopover: some View {
        @Bindable var intentGuard = model.intentGuard
        return VStack(alignment: .leading, spacing: AtelierMetrics.spaceS) {
            Text("Session intent")
                .atelierFont(size: AtelierTypography.caption, weight: .semibold)
                .foregroundStyle(.secondary)
            TextField("What are you working on?", text: $intentGuard.intent)
                .textFieldStyle(.roundedBorder)
                .atelierFont(size: AtelierTypography.body)
                .frame(width: 260)
                .onSubmit { isIntentPopoverPresented = false }
            Text("Gemma quietly flags changed files that do not serve this intent.")
                .atelierFont(size: AtelierTypography.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 260, alignment: .leading)
        }
        .padding(AtelierMetrics.spaceM)
    }

    private var settingsButton: some View {
        Button {
            isSettingsPopoverPresented = true
        } label: {
            Image(systemName: "gearshape")
                .frame(width: AtelierMetrics.spaceL, height: AtelierMetrics.spaceL)
        }
        .buttonStyle(AtelierLuminareIconButtonStyle())
        .popover(isPresented: $isSettingsPopoverPresented, arrowEdge: .bottom) {
            settingsPopover
        }
        .accessibilityLabel("Sidecar settings")
        .help("Sidecar settings")
    }

    private var settingsPopover: some View {
        VStack(alignment: .leading, spacing: AtelierMetrics.spaceS) {
            Text("Background features")
                .atelierFont(size: AtelierTypography.caption, weight: .semibold)
                .foregroundStyle(.secondary)
            Toggle("Auto-diagnose failed commands", isOn: $guardianEnabled)
                .atelierFont(size: AtelierTypography.body)
            Toggle("Session journal", isOn: $journalEnabled)
                .atelierFont(size: AtelierTypography.body)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .padding(AtelierMetrics.spaceM)
        .frame(width: 260, alignment: .leading)
    }

    // MARK: - Feed

    private var feed: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AtelierMetrics.spaceM) {
                    SessionJournalView(model: model.journal)
                    TerminalGuardianCardView(model: model.guardian)
                    PrecommitWhisperView(model: model.whisper)
                    IntentGuardWarningCard(model: model.intentGuard)
                    if feedIsEmpty {
                        emptyFeedState
                    }
                    ForEach(model.interactive.messages) { message in
                        messageView(message)
                            .id(message.id)
                    }
                    ForEach(model.interactive.activities) { activity in
                        activityView(activity)
                            .id(activity.id)
                    }
                    if let error = model.interactive.errorMessage {
                        errorView(error, recovery: model.interactive.recoverySuggestion)
                    }
                    ClaudeBriefingView(model: model.briefing)
                    Color.clear
                        .frame(height: 1)
                        .id("gemma-sidecar-bottom")
                }
                .padding(AtelierMetrics.spaceM)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .atelierScrollChrome(backgroundColor: AppKitThemeAdapter.panel)
            .onChange(of: responseScrollAnchor) {
                proxy.scrollTo("gemma-sidecar-bottom", anchor: .bottom)
            }
        }
    }

    private var feedIsEmpty: Bool {
        model.interactive.messages.isEmpty
            && model.interactive.errorMessage == nil
            && model.journal.entries.isEmpty
            && model.guardian.card == nil
            && !model.guardian.isRunning
            && model.whisper.findings.isEmpty
            && model.intentGuard.activeWarning == nil
    }

    private var responseScrollAnchor: GemmaTranscriptScrollAnchor {
        GemmaTranscriptScrollAnchor(
            messageID: model.interactive.messages.last?.id,
            status: model.interactive.status
        )
    }

    private var emptyFeedState: some View {
        VStack(alignment: .leading, spacing: AtelierMetrics.spaceXS) {
            Text("Gemma is watching this tab")
                .atelierFont(size: AtelierTypography.headline, weight: .semibold, design: .serif)
            Text("Use a quick action or type a prompt. Gemma reads the workspace and cannot make changes.")
                .atelierFont(size: AtelierTypography.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, AtelierMetrics.spaceS)
    }

    private func messageView(_ message: GemmaTranscriptMessage) -> some View {
        VStack(alignment: .leading, spacing: AtelierMetrics.spaceXS) {
            Text(message.role == .user ? "You" : "Gemma")
                .atelierFont(size: AtelierTypography.caption, weight: .semibold)
                .foregroundStyle(message.role == .user ? Color.secondary : AtelierTheme.accent)
            if message.content.isEmpty && model.interactive.isRunning {
                Text("Thinking...")
                    .atelierFont(size: AtelierTypography.caption)
                    .italic()
                    .foregroundStyle(.secondary)
            } else if message.role == .assistant {
                AgentMarkdownView(source: message.content)
                    .textSelection(.enabled)
            } else {
                Text(message.content)
                    .atelierFont(size: AtelierTypography.body)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func activityView(_ activity: GemmaToolActivity) -> some View {
        HStack(spacing: AtelierMetrics.spaceS) {
            Image(systemName: activity.isComplete ? "checkmark.circle" : "ellipsis.circle")
                .atelierFont(size: AtelierTypography.caption)
                .foregroundStyle(activity.isComplete ? AtelierTheme.accent : Color.secondary)
            Text(activity.name)
                .atelierFont(size: AtelierTypography.micro, weight: .semibold, design: .monospaced)
            Text(activity.detail)
                .atelierFont(size: AtelierTypography.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tool \(activity.name), \(activity.detail)")
    }

    private func errorView(_ error: String, recovery: String?) -> some View {
        VStack(alignment: .leading, spacing: AtelierMetrics.spaceXS) {
            Text("Gemma could not finish")
                .atelierFont(size: AtelierTypography.label, weight: .semibold)
                .foregroundStyle(AtelierTheme.danger)
            Text(error)
                .atelierFont(size: AtelierTypography.caption)
                .fixedSize(horizontal: false, vertical: true)
            if let recovery {
                Text(recovery)
                    .atelierFont(size: AtelierTypography.caption, design: .monospaced)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AtelierMetrics.spaceS)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AtelierTheme.danger.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: AtelierTheme.controlRadius, style: .continuous))
    }

    // MARK: - Input zone

    private func inputZone(for context: GemmaSidecarTabContext) -> some View {
        VStack(spacing: 0) {
            chipRow(for: context)
            promptBar
        }
        .background(AtelierTheme.chrome)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AtelierTheme.border)
                .frame(height: AtelierTheme.strokeHairline)
        }
    }

    @ViewBuilder
    private func chipRow(for context: GemmaSidecarTabContext) -> some View {
        let actions = model.allQuickActions(for: context)
        let showsHandoff = model.briefing.activeTerminalContext != nil
        if !actions.isEmpty || showsHandoff {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AtelierMetrics.spaceXS) {
                    ForEach(actions) { action in
                        Button {
                            model.services.runInteractive(action.prompt)
                            isPromptFocused = true
                        } label: {
                            Label(action.title, systemImage: action.systemImage)
                                .labelStyle(.titleAndIcon)
                        }
                        .buttonStyle(AtelierGhostButtonStyle(tint: AtelierTheme.accent))
                        .disabled(model.interactive.isRunning)
                        .accessibilityLabel(action.title)
                    }
                    if showsHandoff {
                        Button {
                            model.briefing.generate()
                        } label: {
                            Label("Claude Handoff", systemImage: "sparkles")
                                .labelStyle(.titleAndIcon)
                        }
                        .buttonStyle(AtelierGhostButtonStyle(tint: AtelierTheme.accent))
                        .disabled(model.briefing.phase == .generating)
                        .accessibilityLabel("Generate a Claude handoff briefing")
                        .help("Summarize the current work state into a prompt for Claude Code")
                    }
                }
                .padding(.horizontal, AtelierMetrics.spaceM)
                .padding(.top, AtelierMetrics.spaceS)
            }
        }
    }

    private var promptBar: some View {
        HStack(alignment: .bottom, spacing: AtelierMetrics.spaceS) {
            TextField("Ask about this tab", text: promptBinding, axis: .vertical)
                .textFieldStyle(.plain)
                .atelierFont(size: AtelierTypography.body)
                .lineLimit(1...4)
                .focused($isPromptFocused)
                .onSubmit(sendPrompt)
                .disabled(model.interactive.isRunning)
                .padding(.horizontal, AtelierMetrics.spaceS)
                .padding(.vertical, AtelierMetrics.spaceS)
                .atelierField(isFocused: isPromptFocused)

            if model.interactive.isRunning {
                Button {
                    model.interactive.stop()
                } label: {
                    Image(systemName: "stop.fill")
                        .frame(width: AtelierMetrics.spaceL, height: AtelierMetrics.spaceL)
                }
                .buttonStyle(AtelierLuminareIconButtonStyle())
                .accessibilityLabel("Stop Gemma")
                .help("Stop Gemma")
            } else {
                Button(action: sendPrompt) {
                    Image(systemName: "arrow.up")
                        .frame(width: AtelierMetrics.spaceL, height: AtelierMetrics.spaceL)
                }
                .buttonStyle(AtelierLuminareIconButtonStyle())
                .disabled(promptIsEmpty)
                .accessibilityLabel("Send to Gemma")
                .help("Send to Gemma")
            }

            Button {
                model.clear()
                isPromptFocused = true
            } label: {
                Image(systemName: "trash")
                    .frame(width: AtelierMetrics.spaceL, height: AtelierMetrics.spaceL)
            }
            .buttonStyle(AtelierLuminareIconButtonStyle())
            .disabled(model.interactive.messages.isEmpty && promptIsEmpty)
            .accessibilityLabel("Clear sidecar session")
            .help("Clear sidecar session")
        }
        .padding(AtelierMetrics.spaceM)
    }

    private var promptBinding: Binding<String> {
        Binding(
            get: { model.interactive.prompt },
            set: { model.interactive.prompt = $0 }
        )
    }

    private var promptIsEmpty: Bool {
        model.interactive.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendPrompt() {
        guard !promptIsEmpty else { return }
        model.interactive.send()
        isPromptFocused = true
    }
}
