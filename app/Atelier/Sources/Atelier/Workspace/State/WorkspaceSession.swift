import Foundation
import Observation

@MainActor
@Observable
final class WorkspaceSession {
    let state: WorkspaceState
    let rootURL: URL
    let terminalTabs: TerminalTabsModel
    let gitModel: GitWorkspaceModel
    private(set) var fileTreeRevision = 0

    private var fileWatcher: FileWatcher?
    private var isStarted = false

    init(state: WorkspaceState, rootURL: URL) {
        self.state = state
        self.rootURL = rootURL
        terminalTabs = TerminalTabsModel(workspacePath: rootURL.path)
        gitModel = GitWorkspaceModel(workspacePath: rootURL.path)
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
        terminalTabs.closeAll()
        AppLogger.workspace.info("Stopped workspace: \(self.rootURL.lastPathComponent, privacy: .public)")
    }

    isolated deinit {
        stop()
    }
}
