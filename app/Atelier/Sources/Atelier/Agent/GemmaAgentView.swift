import AppKit
import SwiftUI

nonisolated struct GemmaTranscriptScrollAnchor: Equatable, Sendable {
    let messageID: UUID?
    let status: GemmaAgentStatus
}

struct GemmaAgentView: View {
    @Bindable var model: GemmaAgentModel
    let workspaceRoot: URL
    let onOpenFile: (URL) -> Void

    @FocusState private var isComposerFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            transcript
            Divider()
            composer
        }
        .background(AtelierTheme.editor)
        .background(GemmaKeyCaptureView(onCharacters: captureKeystroke))
        .onAppear { focusComposer() }
    }

    private func focusComposer() {
        Task { @MainActor in isComposerFocused = true }
    }

    private func captureKeystroke(_ characters: String) -> Bool {
        guard !model.isRunning else { return false }
        model.prompt.append(characters)
        isComposerFocused = true
        return true
    }

    private var header: some View {
        AtelierPanelHeader(
            title: "Gemma Workspace Assistant",
            subtitle: "gemma4:cloud - read-only",
            systemImage: "sparkles"
        ) {
            HStack(spacing: AtelierMetrics.spaceXS) {
                if model.isRunning {
                    ProgressView()
                        .controlSize(.small)
                    Button("Stop") { model.stop() }
                        .buttonStyle(AtelierGhostButtonStyle())
                        .help("Stop Gemma")
                } else if !model.messages.isEmpty {
                    Button("Clear") { model.clear() }
                        .buttonStyle(AtelierGhostButtonStyle())
                        .help("Clear Gemma session")
                }
            }
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: AtelierMetrics.spaceL) {
                    if model.messages.isEmpty {
                        emptyState
                    }
                    ForEach(model.messages) { message in
                        messageView(message)
                            .id(message.id)
                    }
                    ForEach(model.activities) { activity in
                        toolView(activity)
                            .id(activity.id)
                    }
                    if let error = model.errorMessage {
                        errorView(error, recoverySuggestion: model.recoverySuggestion)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id("gemma-transcript-bottom")
                }
                .padding(AtelierMetrics.spaceL)
                .frame(maxWidth: AtelierMetrics.transcriptMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .atelierScrollChrome(backgroundColor: AppKitThemeAdapter.editor)
            .onChange(of: transcriptScrollAnchor) {
                proxy.scrollTo("gemma-transcript-bottom", anchor: .bottom)
            }
        }
    }

    private var transcriptScrollAnchor: GemmaTranscriptScrollAnchor {
        GemmaTranscriptScrollAnchor(
            messageID: model.messages.last?.id,
            status: model.status
        )
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: AtelierMetrics.spaceS) {
            Text("Ask about this workspace")
                .atelierFont(
                    size: AtelierTypography.display,
                    weight: .semibold,
                    design: .serif
                )
                .tracking(-0.4)
            Text("Gemma can search files, read bounded line ranges, and inspect Git diffs. It cannot edit files or run commands.")
                .atelierFont(size: AtelierTypography.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: AtelierMetrics.emptyStateMaxWidth, alignment: .leading)
        .padding(.vertical, AtelierMetrics.spaceXL)
    }

    private func messageView(_ message: GemmaTranscriptMessage) -> some View {
        VStack(alignment: .leading, spacing: AtelierMetrics.spaceXS) {
            Text(message.role == .user ? "You" : "Gemma")
                .atelierFont(size: AtelierTypography.caption, weight: .semibold)
                .foregroundStyle(message.role == .user ? Color.secondary : AtelierTheme.accent)
            if message.content.isEmpty && model.isRunning {
                Text("Thinking...")
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
        .padding(.horizontal, message.role == .user ? AtelierMetrics.spaceM : 0)
        .padding(.vertical, AtelierMetrics.spaceS)
        .background(
            message.role == .user
                ? AtelierTheme.accent.opacity(0.07)
                : Color.clear
        )
        .clipShape(
            RoundedRectangle(cornerRadius: AtelierTheme.controlRadius, style: .continuous)
        )
    }

    private func toolView(_ activity: GemmaToolActivity) -> some View {
        HStack(spacing: AtelierMetrics.spaceS) {
            Image(systemName: activity.isComplete ? "checkmark.circle" : "ellipsis.circle")
                .foregroundStyle(activity.isComplete ? AtelierTheme.accent : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.name)
                    .atelierFont(size: AtelierTypography.micro, weight: .semibold, design: .monospaced)
                Text(activity.detail)
                    .atelierFont(size: AtelierTypography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            if let path = activity.referencedFiles.first {
                Button("Open") { open(path) }
                    .buttonStyle(AtelierGhostButtonStyle(tint: AtelierTheme.accent))
                    .accessibilityLabel("Open \(path)")
            }
        }
        .padding(.horizontal, AtelierMetrics.spaceS)
        .padding(.vertical, AtelierMetrics.spaceS)
        .atelierCard()
    }

    private func errorView(_ error: String, recoverySuggestion: String?) -> some View {
        VStack(alignment: .leading, spacing: AtelierMetrics.spaceXS) {
            Text("Gemma could not finish")
                .atelierFont(size: AtelierTypography.label, weight: .semibold)
                .foregroundStyle(AtelierTheme.danger)
            Text(error)
                .atelierFont(size: AtelierTypography.caption)
            if let recoverySuggestion {
                Text(recoverySuggestion)
                    .atelierFont(size: AtelierTypography.caption, design: .monospaced)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(AtelierMetrics.spaceS)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AtelierTheme.danger.opacity(0.07))
        .clipShape(
            RoundedRectangle(cornerRadius: AtelierTheme.controlRadius, style: .continuous)
        )
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(
                topLeadingRadius: AtelierTheme.controlRadius,
                bottomLeadingRadius: AtelierTheme.controlRadius
            )
            .fill(AtelierTheme.danger)
            .frame(width: 2)
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: AtelierMetrics.spaceS) {
            TextField("Ask Gemma about this workspace", text: $model.prompt, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .focused($isComposerFocused)
                .onSubmit(model.send)
                .disabled(model.isRunning)
                .padding(.horizontal, AtelierMetrics.spaceS)
                .padding(.vertical, AtelierMetrics.spaceS)
                .atelierField(isFocused: isComposerFocused)
            Button {
                model.send()
                isComposerFocused = true
            } label: {
                Image(systemName: "arrow.up")
                    .frame(width: AtelierMetrics.spaceL, height: AtelierMetrics.spaceL)
            }
            .buttonStyle(AtelierLuminareIconButtonStyle())
            .disabled(model.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isRunning)
            .accessibilityLabel("Send to Gemma")
            .help("Send to Gemma")
        }
        .padding(AtelierMetrics.spaceM)
        .background(AtelierTheme.chrome)
    }

    private func open(_ path: String) {
        let url = path.hasPrefix("/")
            ? URL(fileURLWithPath: path)
            : workspaceRoot.appending(path: path)
        let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
        guard resolved.pathComponents.starts(with: workspaceRoot.pathComponents) else { return }
        onOpenFile(resolved)
    }
}

private struct GemmaKeyCaptureView: NSViewRepresentable {
    let onCharacters: (String) -> Bool

    func makeNSView(context: Context) -> NSView {
        let view = KeyCaptureBackingView()
        view.onCharacters = onCharacters
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? KeyCaptureBackingView)?.onCharacters = onCharacters
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        (nsView as? KeyCaptureBackingView)?.removeMonitor()
    }
}

private final class KeyCaptureBackingView: NSView {
    var onCharacters: ((String) -> Bool)?
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { removeMonitor() } else { installMonitor() }
    }

    private func installMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, event.window === window else { return event }
            // Editing a text field already? Let it handle the key.
            if window.firstResponder is NSText { return event }
            guard let characters = Self.captureableCharacters(from: event),
                  self.onCharacters?(characters) == true else { return event }
            return nil
        }
    }

    func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private static func captureableCharacters(from event: NSEvent) -> String? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) || flags.contains(.control) || flags.contains(.option) {
            return nil
        }
        guard let characters = event.characters, !characters.isEmpty else { return nil }
        for scalar in characters.unicodeScalars {
            if scalar.value >= 0xF700 { return nil } // function / arrow keys
            if CharacterSet.controlCharacters.contains(scalar) { return nil } // esc, tab, return
        }
        return characters
    }
}
