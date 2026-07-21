import Foundation
import Observation

@MainActor
@Observable
final class EditorSession {
    let document: EditorDocument
    private let diagnosticSessionID = UUID().uuidString
    private(set) var content: FileContent = .loading
    private(set) var selectedLineRange: ClosedRange<Int>?
    var isWordWrapEnabled = true
    private(set) var diagnosticLoadedBytes = 0
    private(set) var diagnosticLineCount = 0
    private(set) var diagnosticLoadState = "loading"
    private var loadTask: Task<Void, Never>?
    private weak var surface: (any EditorSurface)?

    init(url: URL) {
        document = EditorDocument(url: url.standardizedFileURL)
        reload()
    }

    func reload() {
        if loadTask != nil {
            RuntimeDiagnosticsService.shared.record(
                category: "editorSession",
                name: "loadCancelled",
                correlationID: diagnosticSessionID
            )
            loadTask?.cancel()
        }
        content = .loading
        diagnosticLoadedBytes = 0
        diagnosticLineCount = 0
        diagnosticLoadState = "loading"
        let url = document.url
        RuntimeDiagnosticsService.shared.record(
            category: "editorSession",
            name: "loadStarted",
            correlationID: diagnosticSessionID
        )
        let fileLoadSignpost = RuntimeSignposts.signposter.beginInterval("FileLoad")
        loadTask = Task { [weak self] in
            defer {
                RuntimeSignposts.signposter.endInterval("FileLoad", fileLoadSignpost)
            }
            let content = await FileLoader.loadAsync(url: url)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            self.content = content
            self.updateDiagnosticContentMetrics(content)
            self.loadTask = nil
            RuntimeDiagnosticsService.shared.record(
                category: "editorSession",
                name: "loadCompleted",
                metadata: [
                    "bytes": .integer(self.diagnosticLoadedBytes),
                    "lines": .integer(self.diagnosticLineCount),
                    "state": .string(self.diagnosticLoadState)
                ],
                correlationID: self.diagnosticSessionID
            )
        }
    }

    func close() {
        if loadTask != nil {
            RuntimeDiagnosticsService.shared.record(
                category: "editorSession",
                name: "loadCancelled",
                correlationID: diagnosticSessionID
            )
        }
        loadTask?.cancel()
        loadTask = nil
        surface = nil
        selectedLineRange = nil
    }

    func toggleWordWrap() {
        isWordWrapEnabled.toggle()
        RuntimeDiagnosticsService.shared.record(
            category: "editor",
            name: "wordWrapChanged",
            metadata: ["enabled": .boolean(isWordWrapEnabled)],
            correlationID: runtimeControllerID
        )
    }

    func attach(surface: any EditorSurface) {
        self.surface = surface
        RuntimeDiagnosticsService.shared.record(
            category: "editor",
            name: "nativeEditorAttached",
            correlationID: (surface as? any RuntimeDiagnosableEditorSurface)?.runtimeDiagnosticID
        )
    }

    func detach(surface: any EditorSurface) {
        guard self.surface === surface else { return }
        self.surface = nil
        RuntimeDiagnosticsService.shared.record(
            category: "editor",
            name: "nativeEditorDetached",
            correlationID: (surface as? any RuntimeDiagnosableEditorSurface)?.runtimeDiagnosticID
        )
    }

    var runtimeControllerID: String? {
        (surface as? any RuntimeDiagnosableEditorSurface)?.runtimeDiagnosticID
    }

    func runtimeEditorSnapshot() -> RuntimeEditorSnapshot {
        guard let surface = surface as? any RuntimeDiagnosableEditorSurface else {
            return RuntimeEditorSnapshot(
                contentBytes: diagnosticLoadedBytes,
                lineCount: diagnosticLineCount
            )
        }
        var snapshot = surface.runtimeSnapshot()
        if snapshot.contentBytes == 0 {
            snapshot.contentBytes = diagnosticLoadedBytes
            snapshot.lineCount = diagnosticLineCount
        }
        return snapshot
    }

    func runRuntimeScrollProbe(delta: Double, restore: Bool) async -> (
        status: String,
        elapsedMs: Double,
        result: [String: RuntimeScalar]
    ) {
        guard let surface = surface as? any RuntimeDiagnosableEditorSurface else {
            return ("notApplicable", 0, ["reason": .string("No mounted text editor.")])
        }
        return await surface.runScrollProbe(delta: delta, restore: restore)
    }

    private func updateDiagnosticContentMetrics(_ content: FileContent) {
        switch content {
        case .text(let text):
            diagnosticLoadedBytes = text.utf8.count
            diagnosticLineCount = text.isEmpty ? 0 : text.utf8.reduce(into: 1) { count, byte in
                if byte == 0x0A { count += 1 }
            }
            diagnosticLoadState = "text"
        case .image(let data):
            diagnosticLoadedBytes = data.count
            diagnosticLineCount = 0
            diagnosticLoadState = "image"
        case .loading:
            diagnosticLoadedBytes = 0
            diagnosticLineCount = 0
            diagnosticLoadState = "loading"
        case .binary:
            diagnosticLoadedBytes = 0
            diagnosticLineCount = 0
            diagnosticLoadState = "binary"
        case .tooLarge:
            diagnosticLoadedBytes = 0
            diagnosticLineCount = 0
            diagnosticLoadState = "tooLarge"
        case .error:
            diagnosticLoadedBytes = 0
            diagnosticLineCount = 0
            diagnosticLoadState = "error"
        }
    }

    func performFindAction(_ action: EditorFindAction) {
        guard canFindInFile else { return }
        surface?.performFindAction(action)
    }

    func updateSelection(text: String, range: NSRange) {
        selectedLineRange = EditorSelectionReferencePolicy.lineRange(
            in: text,
            selection: range
        )
    }

    func selectionReference(workspaceRootURL: URL) -> String? {
        guard let selectedLineRange else { return nil }
        return EditorSelectionReferencePolicy.reference(
            fileURL: document.url,
            workspaceRootURL: workspaceRootURL,
            lineRange: selectedLineRange
        )
    }

    /// Bounded plain text of the current selection's line range, for the Gemma
    /// sidecar's "explain selection" action. Nil when there is no selection.
    var selectedText: String? {
        guard let selectedLineRange, case .text(let text) = content else { return nil }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let lower = min(max(0, selectedLineRange.lowerBound - 1), lines.count)
        let upper = min(lines.count, selectedLineRange.upperBound)
        guard lower < upper else { return nil }
        let joined = lines[lower..<upper].joined(separator: "\n")
        return String(joined.prefix(4_000))
    }

    var canFindInFile: Bool {
        if case .text = content { return true }
        return false
    }

    isolated deinit {
        close()
    }
}
