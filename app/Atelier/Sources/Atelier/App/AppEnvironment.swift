import Foundation

@MainActor
struct AppEnvironment {
    let persistence: WorkspacePersistenceService
    let makeWorkspaceAccess: () -> WorkspaceAccessController
    let openFolderPanel: OpenFolderPanel
    let windowController: WindowController
    let layoutProfileDefaults: UserDefaults?
    let scheduleWorkspaceRestore: @MainActor @Sendable () async -> Void

    init(
        persistence: WorkspacePersistenceService,
        makeWorkspaceAccess: @escaping () -> WorkspaceAccessController,
        openFolderPanel: OpenFolderPanel,
        windowController: WindowController,
        layoutProfileDefaults: UserDefaults? = nil,
        scheduleWorkspaceRestore: @escaping @MainActor @Sendable () async -> Void = {
            await Task.yield()
        }
    ) {
        self.persistence = persistence
        self.makeWorkspaceAccess = makeWorkspaceAccess
        self.openFolderPanel = openFolderPanel
        self.windowController = windowController
        self.layoutProfileDefaults = layoutProfileDefaults
        self.scheduleWorkspaceRestore = scheduleWorkspaceRestore
    }

    static func live() -> AppEnvironment {
        AppEnvironment(
            persistence: WorkspacePersistenceService(),
            makeWorkspaceAccess: { WorkspaceAccessController() },
            openFolderPanel: OpenFolderPanel(),
            windowController: WindowController(),
            layoutProfileDefaults: .standard
        )
    }
}
