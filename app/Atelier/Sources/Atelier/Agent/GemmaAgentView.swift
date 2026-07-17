import AppKit
import SwiftUI

struct GemmaAgentView: View {
    @Bindable var model: GemmaAgentModel
    let workspaceRoot: URL
    let onOpenFile: (URL) -> Void

    @FocusState private var isComposerFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
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
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(AtelierTheme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("Gemma Workspace Assistant")
                    .atelierFont(size: 12, weight: .semibold)
                Text("gemma4:cloud - read-only")
                    .atelierFont(size: 9.5, design: .monospaced)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.isRunning {
                ProgressView()
                    .controlSize(.small)
                Button("Stop") { model.stop() }
                    .buttonStyle(.borderless)
                    .help("Stop Gemma")
            } else if !model.messages.isEmpty {
                Button("Clear") { model.clear() }
                    .buttonStyle(.borderless)
                    .help("Clear Gemma session")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(AtelierTheme.chrome)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
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
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .atelierScrollChrome(backgroundColor: AppKitThemeAdapter.editor)
            .onChange(of: model.messages.last?.content) {
                if let id = model.messages.last?.id {
                    proxy.scrollTo(id, anchor: .bottom)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ask about this workspace")
                .atelierFont(size: 20, weight: .semibold)
            Text("Gemma can search files, read bounded line ranges, and inspect Git diffs. It cannot edit files or run commands.")
                .atelierFont(size: 12)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 520, alignment: .leading)
        .padding(.vertical, 24)
    }

    private func messageView(_ message: GemmaTranscriptMessage) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(message.role == .user ? "YOU" : "GEMMA")
                .atelierFont(size: 9, weight: .bold, design: .monospaced)
                .foregroundStyle(message.role == .user ? AtelierTheme.gitOrange : AtelierTheme.accent)
            if message.content.isEmpty && model.isRunning {
                Text("Thinking...")
                    .italic()
                    .foregroundStyle(.secondary)
            } else if message.role == .assistant {
                AgentMarkdownView(source: message.content)
                    .textSelection(.enabled)
            } else {
                Text(message.content)
                    .atelierFont(size: 12.5)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(message.role == .user ? AtelierTheme.panel : AtelierTheme.editor)
        .overlay {
            RoundedRectangle(cornerRadius: AtelierTheme.controlRadius)
                .stroke(AtelierTheme.border, lineWidth: 0.75)
        }
        .clipShape(RoundedRectangle(cornerRadius: AtelierTheme.controlRadius))
    }

    private func toolView(_ activity: GemmaToolActivity) -> some View {
        HStack(spacing: 8) {
            Image(systemName: activity.isComplete ? "checkmark.circle" : "ellipsis.circle")
                .foregroundStyle(activity.isComplete ? AtelierTheme.accent : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.name)
                    .atelierFont(size: 9.5, weight: .semibold, design: .monospaced)
                Text(activity.detail)
                    .atelierFont(size: 10.5)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            if let path = activity.referencedFiles.first {
                Button("Open") { open(path) }
                    .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AtelierTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: AtelierTheme.controlRadius))
    }

    private func errorView(_ error: String, recoverySuggestion: String?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Gemma could not finish")
                .atelierFont(size: 11, weight: .semibold)
                .foregroundStyle(.red)
            Text(error)
                .atelierFont(size: 10.5)
            if let recoverySuggestion {
                Text(recoverySuggestion)
                    .atelierFont(size: 10, design: .monospaced)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.06))
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask Gemma about this workspace", text: $model.prompt, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .focused($isComposerFocused)
                .onSubmit(model.send)
                .disabled(model.isRunning)
            Button {
                model.send()
                isComposerFocused = true
            } label: {
                Image(systemName: "arrow.up")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(AtelierLuminareIconButtonStyle())
            .disabled(model.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isRunning)
            .accessibilityLabel("Send to Gemma")
            .help("Send to Gemma")
        }
        .padding(12)
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
