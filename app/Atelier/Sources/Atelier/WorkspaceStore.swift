import Foundation
import Combine

/// Load/save workspace state ra JSON, resolve security-scoped bookmark.
final class WorkspaceStore: ObservableObject {
    @Published private(set) var current: WorkspaceState?

    /// URL đang giữ security scope (để stop khi đổi workspace).
    private var scopedURL: URL?
    private let fileURL: URL

    /// fileURL tuỳ biến để test; mặc định là Application Support/Atelier/state.json.
    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? WorkspaceStore.defaultStateURL()
        load()
    }

    static func defaultStateURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Atelier/state.json")
    }

    // MARK: - Public

    /// Gán workspace mới, dừng scope cũ, ghi JSON.
    func setWorkspace(_ state: WorkspaceState) {
        stopScope()
        current = state
        _ = resolveAndStartScope(for: state)
        save()
    }

    func clearWorkspace() {
        stopScope()
        current = nil
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let state = try? decoder.decode(WorkspaceState.self, from: data) else { return }

        // Bookmark stale hoặc folder không còn -> về empty state.
        guard let url = resolveAndStartScope(for: state),
              FileManager.default.fileExists(atPath: url.path) else {
            current = nil
            return
        }
        current = state
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)

        if let current, let data = try? encoder.encode(current) {
            try? data.write(to: fileURL, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    // MARK: - Security scope

    /// Resolve bookmark, bắt đầu security scope. Trả về URL đã resolve.
    @discardableResult
    private func resolveAndStartScope(for state: WorkspaceState) -> URL? {
        guard let bookmark = state.bookmark else {
            return URL(fileURLWithPath: state.path)
        }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &stale) else {
            return nil
        }
        if url.startAccessingSecurityScopedResource() {
            scopedURL = url
        }
        return url
    }

    private func stopScope() {
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
    }
}
