@MainActor
struct AppEnvironment {
    let persistence: WorkspacePersistenceService
    let workspaceAccess: WorkspaceAccessController
    let openFolderPanel: OpenFolderPanel
    let windowController: WindowController

    static func live() -> AppEnvironment {
        AppEnvironment(
            persistence: WorkspacePersistenceService(),
            workspaceAccess: WorkspaceAccessController(),
            openFolderPanel: OpenFolderPanel(),
            windowController: WindowController()
        )
    }
}
