import CoreGraphics
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    let zoom: AtelierZoomModel
    let windowController: WindowController
    let layoutProfiles: LayoutProfileStore
    let threadsPanel = ThreadsPanelModel()
    let visibility = WorkspaceVisibilityModel()

    private(set) var workspaceStates: [WorkspaceState] = []
    private(set) var selectedWorkspaceID: String? {
        didSet {
            guard selectedWorkspaceID != oldValue else { return }
            if let selectedWorkspaceID {
                sessionsByID[selectedWorkspaceID]?.activateAgentResponses()
            }
            windowController.setActiveWorkspace(id: selectedWorkspaceID)
        }
    }
    private(set) var loadingWorkspaceIDs = Set<String>()
    private(set) var workspaceFailures: [String: WorkspaceCatalogItemStatus] = [:]
    private(set) var workspaceSidebarWidth = AtelierMetrics.workspaceSidebarIdealWidth
    private(set) var workspaceInspectorWidth = AtelierMetrics.inspectorIdealWidth
    private(set) var currentWindowContentSize: CGSize?
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
    private var layoutProfileApplicationTask: Task<Void, Never>?
    private var layoutProfileApplicationRevision: UInt64 = 0
    private var hasStarted = false
    private var hasStopped = false
    private var isStartupRestorePending = false
    private var pendingDeepLinkURL: URL?

    init(environment: AppEnvironment = .live()) {
        self.environment = environment
        windowController = environment.windowController
        zoom = AtelierZoomModel(windowController: environment.windowController)
        layoutProfiles = LayoutProfileStore(defaults: environment.layoutProfileDefaults)
        let initialProfile = layoutProfiles.selectedProfile.snapshot
        workspaceSidebarWidth = WorkspaceSidebarWidthPolicy.clamped(initialProfile.sidebarWidth)
        workspaceInspectorWidth = WorkspaceInspectorWidthPolicy.clamped(
            initialProfile.inspectorWidth
        )
        environment.windowController.onScreenDidChange = { [weak zoom] in
            zoom?.updateForCurrentDisplay()
        }
        environment.windowController.onContentSizeDidChange = { [weak self] size in
            self?.updateCurrentWindowContentSize(size)
        }
    }

    var selectedLayoutProfile: LayoutProfile {
        layoutProfiles.selectedProfile
    }

    var isSelectedLayoutProfileModified: Bool {
        guard !layoutProfiles.isApplying else { return false }
        return layoutProfiles.isSelectedProfileModified(by: currentLayoutProfileSnapshot())
    }

    func saveCurrentLayoutProfile() {
        let snapshot = currentLayoutProfileSnapshot()
        layoutProfiles.save(snapshot, to: layoutProfiles.selectedID)
        for session in liveSessions {
            session.chrome.applyLayoutProfilePanels(snapshot.panels, requestsAnimation: false)
        }
    }

    func applyLayoutProfile(_ id: LayoutProfileID) {
        let profile = layoutProfiles.profile(for: id)
        layoutProfiles.select(id)
        layoutProfileApplicationRevision &+= 1
        let revision = layoutProfileApplicationRevision
        layoutProfileApplicationTask?.cancel()
        layoutProfiles.beginApplying()
        let responder = windowController.currentFirstResponder()
        if let appliedSize = windowController.applyContentSize(
            profile.snapshot.windowContentSize,
            minimumSize: AtelierZoomModel.baseMinimumSize
        ) {
            updateCurrentWindowContentSize(appliedSize)
        }

        layoutProfileApplicationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if revision == layoutProfileApplicationRevision {
                    layoutProfiles.endApplying()
                    layoutProfileApplicationTask = nil
                }
            }
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled, revision == layoutProfileApplicationRevision else { return }

            zoom.applyLayoutProfileState(profile.snapshot.zoom)
            updateWorkspaceSidebarWidth(profile.snapshot.sidebarWidth)
            updateWorkspaceInspectorWidth(profile.snapshot.inspectorWidth)

            await Task.yield()
            guard !Task.isCancelled, revision == layoutProfileApplicationRevision else { return }
            for session in liveSessions {
                session.chrome.applyLayoutProfilePanels(
                    profile.snapshot.panels,
                    requestsAnimation: false
                )
            }

            await Task.yield()
            guard !Task.isCancelled, revision == layoutProfileApplicationRevision else { return }
            windowController.restoreFirstResponder(responder)
        }
    }

    func updateWorkspaceSidebarWidth(_ proposedWidth: CGFloat) {
        let width = WorkspaceSidebarWidthPolicy.clamped(proposedWidth)
        guard WorkspaceSidebarWidthPolicy.differs(workspaceSidebarWidth, from: width) else {
            return
        }
        workspaceSidebarWidth = width
    }

    func updateWorkspaceInspectorWidth(_ proposedWidth: CGFloat) {
        let width = WorkspaceInspectorWidthPolicy.clamped(proposedWidth)
        guard WorkspaceInspectorWidthPolicy.differs(workspaceInspectorWidth, from: width) else {
            return
        }
        workspaceInspectorWidth = width
    }

    private func currentLayoutProfileSnapshot() -> LayoutProfileSnapshot {
        let selectedSnapshot = layoutProfiles.selectedProfile.snapshot
        let observedWindowSize = currentWindowContentSize
        let windowSize = windowController.currentContentSize()
            ?? observedWindowSize
            ?? selectedSnapshot.windowContentSize
        let panelState = workspace?.chrome.layoutProfilePanelState
            ?? selectedSnapshot.panels
        return LayoutProfileSnapshot(
            windowWidth: windowSize.width,
            windowHeight: windowSize.height,
            zoom: zoom.layoutProfileState,
            sidebarWidth: workspaceSidebarWidth,
            inspectorWidth: workspaceInspectorWidth,
            panels: panelState
        ).normalized()
    }

    private func updateCurrentWindowContentSize(_ size: CGSize) {
        let normalized = CGSize(width: size.width.rounded(), height: size.height.rounded())
        guard currentWindowContentSize != normalized else { return }
        currentWindowContentSize = normalized
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        isStartupRestorePending = true
        visibility.start()
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

    /// Handle an `atelier://open?path=...` deep link. Only workspaces already
    /// present in the catalog are selectable; unknown paths just surface the app.
    func handleDeepLink(_ url: URL) {
        guard url.scheme == "atelier", !hasStopped else { return }
        if isStartupRestorePending {
            pendingDeepLinkURL = url
            return
        }
        windowController.showWorkspaceWindow()
        guard url.host() == "open",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let path = components.queryItems?.first(where: { $0.name == "path" })?.value,
              !path.isEmpty else {
            return
        }
        let workspaceID = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.path
        guard workspaceStates.contains(where: { $0.id == workspaceID }) else {
            AppLogger.workspace.info("Deep link ignored: path is not an open workspace")
            return
        }
        selectWorkspace(id: workspaceID)
    }

    @discardableResult
    func stop() -> Task<Void, Never> {
        if hasStopped {
            return Task { @MainActor [weak self] in
                await self?.flushPersistence()
            }
        }
        hasStopped = true
        visibility.stop()
        startupTask?.cancel()
        startupTask = nil
        layoutProfileApplicationRevision &+= 1
        layoutProfileApplicationTask?.cancel()
        layoutProfileApplicationTask = nil
        layoutProfiles.endApplying()
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
        session.chrome.applyLayoutProfilePanels(
            layoutProfiles.selectedProfile.snapshot.panels,
            requestsAnimation: false
        )
        sessionsByID[state.id] = session
        session.start(agentResponsesActive: state.id == selectedWorkspaceID)
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
        if let url = pendingDeepLinkURL {
            pendingDeepLinkURL = nil
            handleDeepLink(url)
        }
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
