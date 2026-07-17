import Observation

@MainActor
@Observable
final class AppModel {
    let zoom: AtelierZoomModel
    let windowController: WindowController

    private(set) var workspace: WorkspaceSession?
    var presentedError: AppError?

    private let environment: AppEnvironment
    private var startupTask: Task<Void, Never>?
    private var persistenceTask: Task<Void, Never>?
    private var hasStarted = false

    init(environment: AppEnvironment = .live()) {
        self.environment = environment
        windowController = environment.windowController
        zoom = AtelierZoomModel(windowController: environment.windowController)
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        presentLastResourceExitIfNeeded()
        windowController.installGlobalShortcut()
        startupTask = Task { [weak self] in
            guard let self else { return }
            do {
                if let state = try await environment.persistence.load() {
                    guard !Task.isCancelled else { return }
                    try activate(state, persist: false)
                }
            } catch {
                AppLogger.workspace.error("Workspace restore failed: \(error.localizedDescription, privacy: .public)")
                presentedError = .workspace(error)
            }
        }
    }

    func chooseWorkspace() {
        do {
            guard let state = try environment.openFolderPanel.selectWorkspace() else { return }
            try activate(state, persist: true)
        } catch {
            AppLogger.workspace.error("Workspace open failed: \(error.localizedDescription, privacy: .public)")
            presentedError = .workspace(error)
        }
    }

    func closeWorkspace() {
        workspace?.stop()
        workspace = nil
        environment.workspaceAccess.stop()
        persist(nil)
    }

    func stop() {
        startupTask?.cancel()
        startupTask = nil
        persistenceTask?.cancel()
        persistenceTask = nil
        workspace?.stop()
        workspace = nil
        environment.workspaceAccess.stop()
    }

    private func activate(_ state: WorkspaceState, persist shouldPersist: Bool) throws {
        let rootURL = try environment.workspaceAccess.activate(state)
        workspace?.stop()

        let session = WorkspaceSession(state: state, rootURL: rootURL)
        workspace = session
        session.start()
        if shouldPersist { persist(state) }
    }

    private func presentLastResourceExitIfNeeded() {
        guard let url = ResourceExitMarker.defaultURL(),
              let record = ResourceExitMarker.read(from: url) else { return }
        presentedError = .resourceExit(record)
        ResourceExitMarker.clear(at: url)
    }

    private func persist(_ state: WorkspaceState?) {
        persistenceTask?.cancel()
        persistenceTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await environment.persistence.save(state)
            } catch is CancellationError {
                return
            } catch {
                AppLogger.workspace.error("Workspace save failed: \(error.localizedDescription, privacy: .public)")
                presentedError = .workspace(error)
            }
        }
    }
}
