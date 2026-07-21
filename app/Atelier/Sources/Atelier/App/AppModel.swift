import Observation

@MainActor
@Observable
final class AppModel {
    let zoom: AtelierZoomModel
    let windowController: WindowController
    let threadsPanel = ThreadsPanelModel()

    private(set) var workspaceStates: [WorkspaceState] = []
    private(set) var selectedWorkspaceID: String? {
        didSet {
            guard selectedWorkspaceID != oldValue else { return }
            windowController.setActiveWorkspace(id: selectedWorkspaceID)
        }
    }
    private(set) var loadingWorkspaceIDs = Set<String>()
    private(set) var workspaceFailures: [String: WorkspaceCatalogItemStatus] = [:]
    var presentedError: AppError?

    private var sessionsByID: [String: WorkspaceSession] = [:]

    var workspace: WorkspaceSession? {
        guard let selectedWorkspaceID else { return nil }
        return sessionsByID[selectedWorkspaceID]
    }

    var liveSessions: [WorkspaceSession] {
        workspaceStates.compactMap { sessionsByID[$0.id] }
    }

    var workspaceItems: [WorkspaceCatalogItem] {
        workspaceStates.map { state in
            let status: WorkspaceCatalogItemStatus
            if loadingWorkspaceIDs.contains(state.id) {
                status = .loading
            } else if let failure = workspaceFailures[state.id] {
                status = failure
            } else if state.id == selectedWorkspaceID {
                status = .active
            } else {
                status = .inactive
            }
            return WorkspaceCatalogItem(state: state, status: status)
        }
    }

    var selectedWorkspaceItem: WorkspaceCatalogItem? {
        guard let selectedWorkspaceID else { return nil }
        return workspaceItems.first { $0.id == selectedWorkspaceID }
    }

    private let environment: AppEnvironment
    private var startupTask: Task<Void, Never>?
    private var persistenceTask: Task<Void, Never>?
    private var sessionPersistTask: Task<Void, Never>?
    private var pendingPersistence: WorkspaceCatalogState?
    private var catalogMutationRevision: UInt64 = 0
    private var hasStarted = false
    private var hasStopped = false
    private var isStartupRestorePending = false

    init(environment: AppEnvironment = .live()) {
        self.environment = environment
        windowController = environment.windowController
        zoom = AtelierZoomModel(windowController: environment.windowController)
        environment.windowController.onScreenDidChange = { [weak zoom] in
            zoom?.updateForCurrentDisplay()
        }
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        isStartupRestorePending = true
        presentLastResourceExitIfNeeded()
        windowController.installGlobalShortcut()
        let startupMutationRevision = catalogMutationRevision
        startupTask = Task { [weak self] in
            guard let self else { return }
            do {
                if let catalog = try await environment.persistence.load() {
                    guard !Task.isCancelled else {
                        finishStartupRestore()
                        return
                    }
                    await restore(catalog, startupMutationRevision: startupMutationRevision)
                }
                finishStartupRestore()
            } catch {
                finishStartupRestore()
                AppLogger.workspace.error("Workspace restore failed: \(error.localizedDescription, privacy: .public)")
                presentedError = .workspace(error)
            }
        }
    }

    func chooseWorkspace() {
        do {
            guard let state = try environment.openFolderPanel.selectWorkspace() else { return }
            try openWorkspace(state)
        } catch {
            AppLogger.workspace.error("Workspace open failed: \(error.localizedDescription, privacy: .public)")
            presentedError = .workspace(error)
        }
    }

    func closeWorkspace() {
        guard let selectedWorkspaceID else { return }
        closeWorkspace(id: selectedWorkspaceID)
    }

    func closeWorkspace(id workspaceID: String) {
        guard let index = workspaceStates.firstIndex(where: { $0.id == workspaceID }) else { return }
        let wasSelected = workspaceID == selectedWorkspaceID
        catalogMutationRevision &+= 1
        sessionsByID.removeValue(forKey: workspaceID)?.stop()
        workspaceFailures.removeValue(forKey: workspaceID)
        loadingWorkspaceIDs.remove(workspaceID)
        workspaceStates.remove(at: index)

        if wasSelected {
            if workspaceStates.indices.contains(index), sessionsByID[workspaceStates[index].id] != nil {
                selectedWorkspaceID = workspaceStates[index].id
            } else if index > 0, sessionsByID[workspaceStates[index - 1].id] != nil {
                selectedWorkspaceID = workspaceStates[index - 1].id
            } else {
                selectedWorkspaceID = workspaceStates.first { sessionsByID[$0.id] != nil }?.id
            }
        }
        persistCatalog()
    }

    func moveWorkspace(id workspaceID: String, relativeTo targetID: String, insertAfter: Bool) {
        guard workspaceID != targetID,
              let sourceIndex = workspaceStates.firstIndex(where: { $0.id == workspaceID }),
              workspaceStates.contains(where: { $0.id == targetID }) else {
            return
        }

        catalogMutationRevision &+= 1
        let state = workspaceStates.remove(at: sourceIndex)
        guard let targetIndex = workspaceStates.firstIndex(where: { $0.id == targetID }) else {
            workspaceStates.insert(state, at: sourceIndex)
            return
        }
        let insertionIndex = insertAfter ? targetIndex + 1 : targetIndex
        workspaceStates.insert(state, at: insertionIndex)
        persistCatalog()
    }

    func selectNextWorkspace() {
        guard !workspaceStates.isEmpty else { return }
        guard let selectedWorkspaceID,
              let currentIndex = workspaceStates.firstIndex(where: { $0.id == selectedWorkspaceID }) else {
            selectWorkspace(id: workspaceStates[0].id)
            return
        }
        let nextIndex = (currentIndex + 1) % workspaceStates.count
        selectWorkspace(id: workspaceStates[nextIndex].id)
    }

    func selectWorkspace(id: String) {
        guard workspaceStates.contains(where: { $0.id == id }) else { return }
        catalogMutationRevision &+= 1
        selectedWorkspaceID = id
        persistCatalog()
    }

    func selectWorkspace(shortcutNumber: Int) {
        guard let index = WorkspaceRailShortcutPolicy.index(for: shortcutNumber),
              workspaceStates.indices.contains(index) else { return }
        selectWorkspace(id: workspaceStates[index].id)
    }

    func openWorkspace(_ state: WorkspaceState) throws {
        catalogMutationRevision &+= 1
        let standardizedState = WorkspaceState(
            path: state.id,
            bookmark: state.bookmark,
            lastOpenedAt: state.lastOpenedAt
        )
        if sessionsByID[standardizedState.id] != nil {
            selectedWorkspaceID = standardizedState.id
            persistCatalog()
            return
        }

        workspaceStates.removeAll { $0.id == standardizedState.id }
        workspaceStates.append(standardizedState)
        workspaceFailures.removeValue(forKey: standardizedState.id)
        do {
            try activate(standardizedState)
            selectedWorkspaceID = standardizedState.id
            persistCatalog()
        } catch let error as WorkspaceAccessError {
            workspaceFailures[standardizedState.id] = .unavailable(error.localizedDescription)
            selectedWorkspaceID = standardizedState.id
            persistCatalog()
            throw error
        } catch {
            workspaceFailures[standardizedState.id] = .error(error.localizedDescription)
            selectedWorkspaceID = standardizedState.id
            persistCatalog()
            throw error
        }
    }

    @discardableResult
    func stop() -> Task<Void, Never> {
        if hasStopped {
            return Task { @MainActor [weak self] in
                await self?.flushPersistence()
            }
        }
        hasStopped = true
        startupTask?.cancel()
        startupTask = nil
        sessionPersistTask?.cancel()
        sessionPersistTask = nil
        persistCatalog()
        finishStartupRestore()
        sessionsByID.values.forEach { $0.stop() }
        sessionsByID.removeAll()
        loadingWorkspaceIDs.removeAll()
        return Task { @MainActor [weak self] in
            await self?.flushPersistence()
        }
    }

    private func activate(_ state: WorkspaceState) throws {
        let workspaceAccess = environment.makeWorkspaceAccess()
        let rootURL = try workspaceAccess.activate(state)
        let session = WorkspaceSession(
            state: state,
            rootURL: rootURL,
            workspaceAccess: workspaceAccess,
            onSessionChange: { [weak self] in self?.scheduleSessionPersist() }
        )
        sessionsByID[state.id] = session
        session.start()
    }

    private func restore(
        _ catalog: WorkspaceCatalogState,
        startupMutationRevision: UInt64
    ) async {
        for state in catalog.workspaces where !workspaceStates.contains(where: { $0.id == state.id }) {
            workspaceStates.append(state)
        }

        let statesToRestore = catalog.workspaces.filter { sessionsByID[$0.id] == nil }
        loadingWorkspaceIDs.formUnion(statesToRestore.map(\.id))
        await environment.scheduleWorkspaceRestore()

        for state in statesToRestore {
            await Task.yield()
            guard !Task.isCancelled else {
                loadingWorkspaceIDs.subtract(statesToRestore.map(\.id))
                return
            }
            guard workspaceStates.contains(where: { $0.id == state.id }) else {
                loadingWorkspaceIDs.remove(state.id)
                continue
            }
            guard sessionsByID[state.id] == nil else {
                loadingWorkspaceIDs.remove(state.id)
                continue
            }
            do {
                try activate(state)
            } catch let error as WorkspaceAccessError {
                workspaceFailures[state.id] = .unavailable(error.localizedDescription)
                AppLogger.workspace.error(
                    "Workspace restore failed for \(state.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            } catch {
                workspaceFailures[state.id] = .error(error.localizedDescription)
                AppLogger.workspace.error(
                    "Workspace restore failed for \(state.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
            loadingWorkspaceIDs.remove(state.id)
        }

        let userChangedCatalog = startupMutationRevision > 0
            || catalogMutationRevision != startupMutationRevision
        if !userChangedCatalog {
            if let selected = catalog.selectedWorkspaceID, sessionsByID[selected] != nil {
                selectedWorkspaceID = selected
            } else {
                selectedWorkspaceID = workspaceStates.first { sessionsByID[$0.id] != nil }?.id
                    ?? catalog.selectedWorkspaceID
            }
        }
        persistCatalog()
    }

    private func presentLastResourceExitIfNeeded() {
        guard let url = ResourceExitMarker.defaultURL(),
              let record = ResourceExitMarker.read(from: url) else { return }
        presentedError = .resourceExit(record)
        ResourceExitMarker.clear(at: url)
    }

    private func persistCatalog() {
        let workspaces = workspaceStates.map { state -> WorkspaceState in
            guard let session = sessionsByID[state.id] else { return state }
            var updated = state
            updated.session = session.sessionSnapshot()
            return updated
        }
        pendingPersistence = WorkspaceCatalogState(
            workspaces: workspaces,
            selectedWorkspaceID: selectedWorkspaceID
        )
        guard !isStartupRestorePending else { return }
        startPersistenceIfNeeded()
    }

    /// Debounce persistence for high-frequency tab and selection changes so a
    /// burst of edits collapses to one save.
    private func scheduleSessionPersist() {
        guard !isStartupRestorePending, !hasStopped else { return }
        sessionPersistTask?.cancel()
        sessionPersistTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.persistCatalog()
        }
    }

    private func startPersistenceIfNeeded() {
        guard persistenceTask == nil else { return }
        persistenceTask = Task { [weak self] in
            await self?.drainPersistence()
        }
    }

    private func finishStartupRestore() {
        guard isStartupRestorePending else { return }
        isStartupRestorePending = false
        startPersistenceIfNeeded()
    }

    private func drainPersistence() async {
        while let catalog = pendingPersistence {
            pendingPersistence = nil
            do {
                try await environment.persistence.save(catalog)
            } catch {
                AppLogger.workspace.error("Workspace save failed: \(error.localizedDescription, privacy: .public)")
                presentedError = .workspace(error)
            }
        }
        persistenceTask = nil
    }

    private func flushPersistence() async {
        while let persistenceTask {
            await persistenceTask.value
        }
    }
}
