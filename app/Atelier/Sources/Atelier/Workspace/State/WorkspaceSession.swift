import Foundation
import Observation

@MainActor
@Observable
final class WorkspaceSession {
    let state: WorkspaceState
    let rootURL: URL
    let terminalTabs: TerminalTabsModel
    let paletteModel: AtelierPaletteModel
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
    private var fileWatcher: FileWatcher?
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
        let tabs = TerminalTabsModel(
            workspacePath: rootURL.path,
            restoring: state.session
        )
        tabs.onSessionChange = onSessionChange
        terminalTabs = tabs
        paletteModel = AtelierPaletteModel(
            fileIndex: WorkspaceFileIndex(rootURL: rootURL),
            recentFiles: { tabs.recentFileURLs }
        )
        gitModel = GitWorkspaceModel(
            workspacePath: rootURL.path,
            onRepositoryChange: tabs.invalidateGitDiffs
        )
        if let gemmaAgent {
            self.gemmaAgent = gemmaAgent
        } else {
            let client = OllamaCloudClient()
            let toolExecutor = WorkspaceToolExecutor(workspaceRoot: rootURL)
            self.gemmaAgent = GemmaAgentModel(
                runtime: GemmaAgentRuntime(client: client, tools: toolExecutor)
            )
        }
        self.agentResponses = agentResponses ?? AgentResponsesModel(
            source: AgentTranscriptMonitor(workspacePath: rootURL.path)
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
        gitModel.refresh()
        watchtower.setRoot(rootURL.path)
        if agentResponsesActive {
            agentResponses.start()
        }
        gemmaSidecar.start()

        let watcher = FileWatcher(path: rootURL.path) { [weak self] invalidation in
            guard let self else { return }
            if invalidation.contains(.workspaceContent) {
                invalidateFileTree()
            }
            if invalidation.contains(.watchtowerPlan) {
                watchtower.refresh()
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
            watchtower.setRoot(nil)
            gitModel.stop()
            gemmaAgent.close()
            gemmaSidecar.stop()
            agentResponses.stop()
            paletteModel.stop()
            terminalTabs.closeAll()
            AppLogger.workspace.info("Stopped workspace: \(self.rootURL.lastPathComponent, privacy: .public)")
        }
        workspaceAccess?.stop()
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
        paletteModel.updateFileRevision(fileTreeRevision)
    }

    isolated deinit {
        stop()
    }
}
