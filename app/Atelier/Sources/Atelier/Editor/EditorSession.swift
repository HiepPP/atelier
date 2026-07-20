import Foundation
import Observation

@MainActor
@Observable
final class EditorSession {
    let document: EditorDocument
    private(set) var content: FileContent = .loading
    private(set) var selectedLineRange: ClosedRange<Int>?
    var isWordWrapEnabled = true
    private var loadTask: Task<Void, Never>?
    private weak var surface: (any EditorSurface)?

    init(url: URL) {
        document = EditorDocument(url: url.standardizedFileURL)
        reload()
    }

    func reload() {
        loadTask?.cancel()
        content = .loading
        let url = document.url
        loadTask = Task { [weak self] in
            let content = await FileLoader.loadAsync(url: url)
            guard !Task.isCancelled else { return }
            self?.content = content
        }
    }

    func close() {
        loadTask?.cancel()
        loadTask = nil
        surface = nil
        selectedLineRange = nil
    }

    func toggleWordWrap() {
        isWordWrapEnabled.toggle()
    }

    func attach(surface: any EditorSurface) {
        self.surface = surface
    }

    func detach(surface: any EditorSurface) {
        guard self.surface === surface else { return }
        self.surface = nil
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
