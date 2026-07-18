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
    let agentResponses: AgentResponsesModel
    private(set) var fileTreeRevision = 0
    private(set) var isAgentSidecarPresented = false

    private let fileTreeService = FileTreeService()
    private var fileWatcher: FileWatcher?
    private(set) var isStarted = false
    private let workspaceAccess: WorkspaceAccessController?

    init(
        state: WorkspaceState,
        rootURL: URL,
        workspaceAccess: WorkspaceAccessController? = nil,
        gemmaAgent: GemmaAgentModel? = nil,
        agentResponses: AgentResponsesModel? = nil
    ) {
        self.state = state
        self.rootURL = rootURL
        self.workspaceAccess = workspaceAccess
        let tabs = TerminalTabsModel(workspacePath: rootURL.path)
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
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        gitModel.refresh()
        agentResponses.start()

        let watcher = FileWatcher(path: rootURL.path) { [weak self] in
            guard let self else { return }
            invalidateFileTree()
            gitModel.invalidate()
        }
        fileWatcher = watcher
        watcher.start()
        AppLogger.workspace.info("Started workspace: \(self.rootURL.lastPathComponent, privacy: .public)")
    }

    func stop() {
        if isStarted {
            isStarted = false
            fileWatcher?.stop()
            fileWatcher = nil
            gitModel.stop()
            gemmaAgent.close()
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

    private func invalidateFileTree() {
        fileTreeRevision &+= 1
        paletteModel.updateFileRevision(fileTreeRevision)
    }

    isolated deinit {
        stop()
    }
}
