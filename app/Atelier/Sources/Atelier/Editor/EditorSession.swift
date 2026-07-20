import Foundation
import Observation

@MainActor
@Observable
final class EditorSession {
    let document: EditorDocument
    private(set) var content: FileContent = .loading
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

    var canFindInFile: Bool {
        if case .text = content { return true }
        return false
    }

    isolated deinit {
        close()
    }
}
