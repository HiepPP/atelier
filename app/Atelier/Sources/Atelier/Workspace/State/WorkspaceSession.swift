import Foundation
import Observation

@MainActor
@Observable
final class WorkspaceSession {
    let state: WorkspaceState
    let rootURL: URL
    let terminalTabs: TerminalTabsModel
    let paletteModel: AtelierPaletteModel
    let workspaceSearchModel: WorkspaceSearchModel
    let gitModel: GitWorkspaceModel
    let gemmaAgent: GemmaAgentModel
    let gemmaSidecar: GemmaSidecarModel
    let agentResponses: AgentResponsesModel
    let chrome = WorkspaceChromeModel()
    let watchtower = WatchtowerModel()
    private(set) var fileTreeRevision = 0
    private(set) var isAgentSidecarPresented = false
    private(set) var isWatchtowerPresented = false

    private let fileTreeService = FileTreeService()
    private let workspaceSearchRuntimeContext: WorkspaceGemmaSearchRuntimeContext
    private let gitNexusSearchClient: any GitNexusCodeIntelligence
    private var fileWatcher: FileWatcher?
    @ObservationIgnored private var fileTreeInvalidationTask: Task<Void, Never>?
    @ObservationIgnored private var lastFileTreeInvalidationSpawn: ContinuousClock.Instant?
    @ObservationIgnored private var firstPendingFileTreeEvent: ContinuousClock.Instant?
    private(set) var isStarted = false
    private let workspaceAccess: WorkspaceAccessController?

    init(
        state: WorkspaceState,
        rootURL: URL,
        workspaceAccess: WorkspaceAccessController? = nil,
        gemmaAgent: GemmaAgentModel? = nil,
        agentResponses: AgentResponsesModel? = nil,
        onSessionChange: @escaping () -> Void = {}
    ) {
        self.state = state
        self.rootURL = rootURL
        self.workspaceAccess = workspaceAccess
        let searchRuntimeContext = WorkspaceGemmaSearchRuntimeContext()
        workspaceSearchRuntimeContext = searchRuntimeContext
        let tabs = TerminalTabsModel(
            workspacePath: rootURL.path,
            restoring: state.session
        )
        tabs.onSessionChange = onSessionChange
        terminalTabs = tabs
        let fileIndex = WorkspaceFileIndex(rootURL: rootURL)
        paletteModel = AtelierPaletteModel(
            fileIndex: fileIndex,
            workspaceRoot: rootURL,
            recentFiles: { tabs.recentFileURLs }
        )
        let git = GitWorkspaceModel(
            workspacePath: rootURL.path,
            onRepositoryChange: tabs.invalidateGitDiffs
        )
        gitModel = git
        let searchService = WorkspaceSearchService(fileIndex: fileIndex)
        let workspaceTools = WorkspaceToolExecutor(workspaceRoot: rootURL)
        let gitNexusSearchClient = GitNexusMCPClient(workspaceRoot: rootURL)
        self.gitNexusSearchClient = gitNexusSearchClient
        let gemmaSearchTools = WorkspaceGemmaToolExecutor(
            workspaceRoot: rootURL,
            searcher: searchService,
            reader: workspaceTools,
            gitNexus: gitNexusSearchClient,
            context: {
                WorkspaceGemmaSearchToolContext(
                    revision: searchRuntimeContext.revision,
                    ignoredPaths: git.snapshot.status.ignoredPaths
                )
            }
        )
        let gemmaSearch = WorkspaceGemmaSearchModel(
            searcher: WorkspaceGemmaSearchRuntime(
                client: OllamaCloudClient(),
                tools: gemmaSearchTools
            )
        )
        workspaceSearchModel = WorkspaceSearchModel(
            searcher: searchService,
            gemmaSearch: gemmaSearch,
            ignoredPaths: { git.snapshot.status.ignoredPaths }
        )
        if let gemmaAgent {
            self.gemmaAgent = gemmaAgent
        } else {
            let client = OllamaCloudClient()
            self.gemmaAgent = GemmaAgentModel(
                runtime: GemmaAgentRuntime(client: client, tools: workspaceTools)
            )
        }
        self.agentResponses = agentResponses ?? AgentResponsesModel(
            source: AgentTranscriptMonitor(
                workspacePath: rootURL.path,
                modifiedAfter: Date().addingTimeInterval(
                    -AgentTranscriptMonitor.defaultHistoryWindow
                )
            )
        )
        gemmaSidecar = GemmaSidecarModel(
            terminalTabs: tabs,
            gitModel: gitModel,
            workspaceRoot: rootURL
        )
    }

    func start(agentResponsesActive: Bool = true) {
        guard !isStarted else { return }
        isStarted = true
        gitModel.refresh(fetchingRemote: true)
        let watchtowerRoot = rootURL.path
        Task { [weak self] in await self?.watchtower.setRoot(watchtowerRoot) }
        if agentResponsesActive {
            agentResponses.start()
        }
        gemmaSidecar.start()

        let watcher = FileWatcher(path: rootURL.path) { [weak self] invalidation in
            guard let self else { return }
            if invalidation.contains(.workspaceContent) {
                scheduleFileTreeInvalidation()
            }
            if invalidation.contains(.watchtowerPlan) {
                Task { [weak self] in await self?.watchtower.refresh() }
            }
            gitModel.invalidate(
                repositoryMetadataChanged: invalidation.contains(.gitMetadata)
            )
        }
        fileWatcher = watcher
        watcher.start()
        AppLogger.workspace.info("Started workspace: \(self.rootURL.lastPathComponent, privacy: .public)")
    }

    func activateAgentResponses() {
        guard isStarted else { return }
        agentResponses.start()
    }

    func stop() {
        if isStarted {
            isStarted = false
            fileWatcher?.stop()
            fileWatcher = nil
            fileTreeInvalidationTask?.cancel()
            fileTreeInvalidationTask = nil
            firstPendingFileTreeEvent = nil
            watchtower.clear()
            gitModel.stop()
            gemmaAgent.close()
            gemmaSidecar.stop()
            agentResponses.stop()
            paletteModel.stop()
            workspaceSearchModel.stop()
            terminalTabs.closeAll()
            AppLogger.workspace.info("Stopped workspace: \(self.rootURL.lastPathComponent, privacy: .public)")
        }
        workspaceAccess?.stop()
        let gitNexusSearchClient = gitNexusSearchClient
        Task { await gitNexusSearchClient.stop() }
    }

    func createFile(named name: String, in directory: URL) async throws {
        let url = try await fileTreeService.createFile(named: name, in: directory)
        invalidateFileTree()
        terminalTabs.openFile(url)
        AppLogger.fileTree.info("Created file: \(url.lastPathComponent, privacy: .public)")
    }

    func createFolder(named name: String, in directory: URL) async throws {
        let url = try await fileTreeService.createFolder(named: name, in: directory)
        invalidateFileTree()
        AppLogger.fileTree.info("Created folder: \(url.lastPathComponent, privacy: .public)")
    }

    func renameItem(at url: URL, to name: String) async throws {
        let selectedFileURL = terminalTabs.selectedFileURL
        let destination = try await fileTreeService.renameItem(at: url, to: name)
        let replacement = selectedFileURL.flatMap {
            FileTreePathPolicy.replacingRoot(of: $0, from: url, to: destination)
        }
        terminalTabs.closeFiles(atOrUnder: url)
        if let replacement { terminalTabs.openFile(replacement) }
        invalidateFileTree()
        gitModel.invalidate()
        AppLogger.fileTree.info(
            "Renamed item: \(url.lastPathComponent, privacy: .public) to \(destination.lastPathComponent, privacy: .public)"
        )
    }

    func moveItemToTrash(at url: URL) async throws {
        try await fileTreeService.moveToTrash(url)
        terminalTabs.closeFiles(atOrUnder: url)
        invalidateFileTree()
        gitModel.invalidate()
        AppLogger.fileTree.info("Moved item to Trash: \(url.lastPathComponent, privacy: .public)")
    }

    func addItemToGitIgnore(_ url: URL) async throws {
        try await fileTreeService.addToGitIgnore(url, workspaceRoot: rootURL)
        invalidateFileTree()
        gitModel.invalidate()
        AppLogger.fileTree.info("Added item to .gitignore: \(url.lastPathComponent, privacy: .public)")
    }

    func openGemma() {
        terminalTabs.openGemma(gemmaAgent)
    }

    func openAgentSidecar() {
        isAgentSidecarPresented = true
    }

    func toggleAgentSidecar() {
        isAgentSidecarPresented.toggle()
    }

    func closeAgentSidecar() {
        isAgentSidecarPresented = false
    }

    func toggleWatchtower() {
        isWatchtowerPresented.toggle()
    }

    func closeWatchtower() {
        isWatchtowerPresented = false
    }

    /// Current open tabs, for catalog persistence.
    func sessionSnapshot() -> WorkspaceSessionState {
        terminalTabs.sessionSnapshot()
    }

    private func invalidateFileTree() {
        fileTreeRevision &+= 1
        workspaceSearchRuntimeContext.revision = fileTreeRevision
        paletteModel.updateFileRevision(fileTreeRevision)
        workspaceSearchModel.updateFileRevision(fileTreeRevision)
    }

    /// Watcher-driven invalidation. A workspace write burst delivers watcher
    /// events about twice per second, and each revision bump re-renders every
    /// consumer and re-lists expanded file-tree directories. Space bumps at
    /// least two seconds apart with a trailing delay, so the burst collapses
    /// while the final state still lands. The max-wait bound keeps a sustained
    /// burst from deferring the bump forever. Direct user actions (create,
    /// rename, trash) keep calling `invalidateFileTree` for an immediate update.
    private func scheduleFileTreeInvalidation() {
        fileTreeInvalidationTask?.cancel()
        if firstPendingFileTreeEvent == nil {
            firstPendingFileTreeEvent = .now
        }
        let delay = GitRefreshThrottlePolicy.delay(
            sinceLastSpawn: lastFileTreeInvalidationSpawn.map { ContinuousClock.now - $0 },
            sinceFirstPendingEvent: firstPendingFileTreeEvent.map { ContinuousClock.now - $0 }
        )
        // Past the deadline the next event would cancel any scheduled task, so
        // bump inline. This runs from the watcher callback, never a layout pass.
        guard delay > .zero else {
            fileTreeInvalidationTask = nil
            spawnFileTreeInvalidation()
            return
        }
        fileTreeInvalidationTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            spawnFileTreeInvalidation()
        }
    }

    private func spawnFileTreeInvalidation() {
        lastFileTreeInvalidationSpawn = .now
        firstPendingFileTreeEvent = nil
        invalidateFileTree()
    }

    isolated deinit {
        stop()
    }
}
