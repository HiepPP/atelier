import Foundation
import Observation

@MainActor
@Observable
final class EditorSession {
    let document: EditorDocument
    private(set) var content: FileContent = .loading
    private var loadTask: Task<Void, Never>?

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
    }

    isolated deinit {
        close()
    }
}
