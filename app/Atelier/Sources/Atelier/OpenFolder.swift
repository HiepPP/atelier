import AppKit

/// Mở NSOpenPanel chọn folder, tạo security-scoped bookmark.
enum OpenFolder {
    static func pick() -> WorkspaceState? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Mở"

        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        let bookmark = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil)

        return WorkspaceState(path: url.path, bookmark: bookmark, lastOpenedAt: Date())
    }
}
