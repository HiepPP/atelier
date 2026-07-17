import Foundation
import Observation

@MainActor
@Observable
final class WorkspaceSession {
    let state: WorkspaceState
    let rootURL: URL
    let terminalTabs: TerminalTabsModel
    let gitModel: GitWorkspaceModel
    let gemmaAgent: GemmaAgentModel
    private(set) var fileTreeRevision = 0

    private let fileTreeService = FileTreeService()
    private var fileWatcher: FileWatcher?
    private var isStarted = false

    init(state: WorkspaceState, rootURL: URL, gemmaAgent: GemmaAgentModel? = nil) {
        self.state = state
        self.rootURL = rootURL
        terminalTabs = TerminalTabsModel(workspacePath: rootURL.path)
        gitModel = GitWorkspaceModel(workspacePath: rootURL.path)
        if let gemmaAgent {
            self.gemmaAgent = gemmaAgent
        } else {
            let client = OllamaCloudClient()
            let toolExecutor = WorkspaceToolExecutor(workspaceRoot: rootURL)
            self.gemmaAgent = GemmaAgentModel(
                runtime: GemmaAgentRuntime(client: client, tools: toolExecutor)
            )
        }
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        gitModel.refresh()

        let watcher = FileWatcher(path: rootURL.path) { [weak self] in
            guard let self else { return }
            fileTreeRevision &+= 1
            gitModel.invalidate()
        }
        fileWatcher = watcher
        watcher.start()
        AppLogger.workspace.info("Started workspace: \(self.rootURL.lastPathComponent, privacy: .public)")
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        fileWatcher?.stop()
        fileWatcher = nil
        gitModel.stop()
        gemmaAgent.close()
        terminalTabs.closeAll()
        AppLogger.workspace.info("Stopped workspace: \(self.rootURL.lastPathComponent, privacy: .public)")
    }

    func createFile(named name: String, in directory: URL) async throws {
        let url = try await fileTreeService.createFile(named: name, in: directory)
        fileTreeRevision &+= 1
        terminalTabs.openFile(url)
        AppLogger.fileTree.info("Created file: \(url.lastPathComponent, privacy: .public)")
    }

    func createFolder(named name: String, in directory: URL) async throws {
        let url = try await fileTreeService.createFolder(named: name, in: directory)
        fileTreeRevision &+= 1
        AppLogger.fileTree.info("Created folder: \(url.lastPathComponent, privacy: .public)")
    }

    func openGemma() {
        terminalTabs.openGemma(gemmaAgent)
    }

    isolated deinit {
        stop()
    }
}
