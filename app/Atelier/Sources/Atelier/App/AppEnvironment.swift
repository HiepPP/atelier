@MainActor
struct AppEnvironment {
    let persistence: WorkspacePersistenceService
    let makeWorkspaceAccess: () -> WorkspaceAccessController
    let openFolderPanel: OpenFolderPanel
    let windowController: WindowController
    let scheduleWorkspaceRestore: @MainActor @Sendable () async -> Void

    init(
        persistence: WorkspacePersistenceService,
        makeWorkspaceAccess: @escaping () -> WorkspaceAccessController,
        openFolderPanel: OpenFolderPanel,
        windowController: WindowController,
        scheduleWorkspaceRestore: @escaping @MainActor @Sendable () async -> Void = {
            await Task.yield()
        }
    ) {
        self.persistence = persistence
        self.makeWorkspaceAccess = makeWorkspaceAccess
        self.openFolderPanel = openFolderPanel
        self.windowController = windowController
        self.scheduleWorkspaceRestore = scheduleWorkspaceRestore
    }

    static func live() -> AppEnvironment {
        AppEnvironment(
            persistence: WorkspacePersistenceService(),
            makeWorkspaceAccess: { WorkspaceAccessController() },
            openFolderPanel: OpenFolderPanel(),
            windowController: WindowController()
        )
    }
}
