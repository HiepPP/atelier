import Foundation

/// Trạng thái workspace được persist ra JSON.
nonisolated struct WorkspaceState: Codable, Equatable, Sendable, Identifiable {
    var path: String
    var bookmark: Data?
    var lastOpenedAt: Date

    var id: String {
        URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.path
    }
}

nonisolated struct WorkspaceCatalogState: Codable, Equatable, Sendable {
    var workspaces: [WorkspaceState]
    var selectedWorkspaceID: String?

    init(workspaces: [WorkspaceState], selectedWorkspaceID: String?) {
        var seen = Set<String>()
        self.workspaces = workspaces.filter { seen.insert($0.id).inserted }
        self.selectedWorkspaceID = selectedWorkspaceID
    }

    static let empty = WorkspaceCatalogState(workspaces: [], selectedWorkspaceID: nil)
}

nonisolated enum WorkspaceCatalogItemStatus: Equatable, Sendable {
    case active
    case inactive
    case loading
    case unavailable(String)
    case error(String)
}

nonisolated struct WorkspaceCatalogItem: Identifiable, Equatable, Sendable {
    let state: WorkspaceState
    let status: WorkspaceCatalogItemStatus

    var id: String { state.id }
}
