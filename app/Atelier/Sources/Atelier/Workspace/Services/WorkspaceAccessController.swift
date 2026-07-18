import Foundation

enum WorkspaceAccessError: LocalizedError {
    case bookmark(String)
    case missing(String)

    var errorDescription: String? {
        switch self {
        case .bookmark(let message):
            "Could not restore folder access: \(message)"
        case .missing(let path):
            "Workspace folder no longer exists: \(path)"
        }
    }
}

@MainActor
final class WorkspaceAccessController {
    private var scopedURL: URL?
    private(set) var isActive = false

    func activate(_ state: WorkspaceState) throws -> URL {
        stop()

        let url: URL
        if let bookmark = state.bookmark {
            var stale = false
            do {
                url = try URL(
                    resolvingBookmarkData: bookmark,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &stale
                )
            } catch {
                throw WorkspaceAccessError.bookmark(error.localizedDescription)
            }
        } else {
            url = URL(fileURLWithPath: state.path, isDirectory: true)
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw WorkspaceAccessError.missing(url.path)
        }
        if url.startAccessingSecurityScopedResource() {
            scopedURL = url
        }
        isActive = true
        return url
    }

    func stop() {
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
        isActive = false
    }
}
