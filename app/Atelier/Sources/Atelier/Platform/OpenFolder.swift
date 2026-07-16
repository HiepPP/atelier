import AppKit

enum OpenFolderPanelError: LocalizedError {
    case bookmark(String)

    var errorDescription: String? {
        switch self {
        case .bookmark(let message):
            "Could not save folder access: \(message)"
        }
    }
}

@MainActor
struct OpenFolderPanel {
    func selectWorkspace() throws -> WorkspaceState? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Mở"

        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        let bookmark: Data
        do {
            bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            throw OpenFolderPanelError.bookmark(error.localizedDescription)
        }

        return WorkspaceState(path: url.path, bookmark: bookmark, lastOpenedAt: Date())
    }
}
