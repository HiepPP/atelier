import Foundation

nonisolated enum PersistedTabKind: String, Codable, Sendable {
    case file
    case terminal
}

/// One restorable center tab. File tabs carry a path and view state; terminal
/// tabs carry only a title (the running process and scrollback cannot persist).
nonisolated struct PersistedTab: Codable, Equatable, Sendable {
    var kind: PersistedTabKind
    var path: String?
    var isPreview: Bool
    var isWordWrapEnabled: Bool
    var title: String?
}

/// A workspace's open center tabs, restored on relaunch.
nonisolated struct WorkspaceSessionState: Codable, Equatable, Sendable {
    var tabs: [PersistedTab]
    var selectedTabIndex: Int?
}

/// Trạng thái workspace được persist ra JSON.
nonisolated struct WorkspaceState: Codable, Equatable, Sendable, Identifiable {
    var path: String
    var bookmark: Data?
    var lastOpenedAt: Date
    var session: WorkspaceSessionState?

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
