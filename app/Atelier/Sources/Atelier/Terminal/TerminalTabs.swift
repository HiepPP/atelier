import AppKit
import Observation
import SwiftUI

nonisolated enum FileTabDisposition: Equatable, Sendable {
    case preview
    case permanent
}

nonisolated enum TerminalTabInspectorKind: String, Equatable, Sendable {
    case terminal = "Terminal"
    case file = "File"
    case gitDiff = "Git diff"
    case gemma = "Gemma"
}

nonisolated struct TerminalTabInspectorDetail: Equatable, Sendable {
    let label: String
    let value: String
}

nonisolated struct TerminalTabInspectorContext: Equatable, Sendable {
    let kind: TerminalTabInspectorKind
    let title: String
    let systemImage: String
    let status: String
    let details: [TerminalTabInspectorDetail]
    let showsActivity: Bool
}

nonisolated struct TerminalCloseConfirmation: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
}

nonisolated enum TerminalClosePolicy {
    static func requiresConfirmation(foregroundAgentName: String?) -> Bool {
        foregroundAgentName == "claude" || foregroundAgentName == "codex"
    }
}

nonisolated enum AgentSidecarLayoutPolicy {
    static func width(
        availableWidth: CGFloat,
        mode: AgentResponseOverlayMode
    ) -> CGFloat {
        let fullWidth = max(0, availableWidth)
        return mode == .full ? fullWidth : fullWidth / 2
    }
}

nonisolated enum AgentResponseOverlayMode: Equatable, Sendable {
    case full
    case half
}

final class TerminalSession: Identifiable {
    let id = UUID()
    let title: String
    let controller: TerminalController

    init(number: Int, workspacePath: String) {
        title = "Terminal \(number)"
        controller = TerminalController(workspacePath: workspacePath)
    }

    func close() {
        controller.close()
    }

    isolated deinit {
        close()
    }

}

struct OpenTerminalTab {
    let id: UUID
    let title: String
    let controller: TerminalController
}

private enum CenterTabContent {
    case terminal(TerminalSession)
    case file(EditorSession)
    case gitDiff(GitDiffSession)
    case gemma(GemmaAgentModel)
}

private final class CenterTab: Identifiable {
    let id: UUID
    let content: CenterTabContent
    let customTitle: String?
    let fileDisposition: FileTabDisposition?

    init(
        id: UUID = UUID(),
        content: CenterTabContent,
        customTitle: String? = nil,
        fileDisposition: FileTabDisposition? = nil
    ) {
        self.id = id
        self.content = content
        self.customTitle = customTitle
        self.fileDisposition = fileDisposition
    }

    var isPreview: Bool { fileDisposition == .preview }

    var title: String {
        if let customTitle { return customTitle }
        switch content {
        case .terminal(let session):
            return session.title
        case .file(let file):
            return file.document.displayName
        case .gitDiff(let diff):
            return "\(diff.selection.displayName) [\(diff.selection.stateLabel)]"
        case .gemma:
            return "Gemma"
        }
    }

    var systemImage: String {
        switch content {
        case .terminal:
            return "terminal"
        case .file:
            return "doc.text"
        case .gitDiff:
            return "doc.text.magnifyingglass"
        case .gemma:
            return "sparkles"
        }
    }

    var closeHelp: String {
        switch content {
        case .terminal:
            return "Close terminal"
        case .file:
            return "Close file"
        case .gitDiff:
            return "Close Git diff"
        case .gemma:
            return "Close Gemma"
        }
    }
}

@Observable
final class TerminalTabsModel {
    private var tabs: [CenterTab] = []
    private var recentFiles = RecentFileHistory()
    private var fileNavigationHistory = FileNavigationHistory()
    private var lastSelectedTerminalID: UUID?
    private var terminalCommandFinished: ((Int32) -> Void)?
    private let gitDiffCache = GitDiffCache()
    private(set) var pendingTerminalCloseConfirmation: TerminalCloseConfirmation?
    var selectedID: UUID? {
        didSet {
            guard selectedID != oldValue else { return }
            onSessionChange?()
        }
    }

    /// Fires (after init) when the open tab set or selection changes, so the app
    /// can debounce-persist the session. Nil during init/restore to stay quiet.
    var onSessionChange: (() -> Void)?

    fileprivate let workspacePath: String
    private var nextNumber = 1

    init(workspacePath: String, restoring session: WorkspaceSessionState? = nil) {
        self.workspacePath = workspacePath
        if let session, !session.tabs.isEmpty {
            restore(from: session)
        } else {
            add()
        }
    }

    /// Snapshot the open center tabs for persistence. Git diff and Gemma tabs are
    /// not restorable, so they are omitted.
    func sessionSnapshot() -> WorkspaceSessionState {
        var persisted: [PersistedTab] = []
        var selectedTabIndex: Int?
        for tab in tabs {
            switch tab.content {
            case .file(let file):
                persisted.append(PersistedTab(
                    kind: .file,
                    path: file.document.url.path,
                    isPreview: tab.isPreview,
                    isWordWrapEnabled: file.isWordWrapEnabled,
                    title: nil
                ))
            case .terminal(let session):
                persisted.append(PersistedTab(
                    kind: .terminal,
                    path: nil,
                    isPreview: false,
                    isWordWrapEnabled: false,
                    title: tab.customTitle ?? session.title
                ))
            case .gitDiff, .gemma:
                continue
            }
            if tab.id == selectedID {
                selectedTabIndex = persisted.count - 1
            }
        }
        return WorkspaceSessionState(tabs: persisted, selectedTabIndex: selectedTabIndex)
    }

    /// Rebuild tabs from a saved session. Skips files that no longer exist and
    /// reopens terminals as fresh shells. Falls back to one terminal if empty.
    private func restore(from session: WorkspaceSessionState) {
        var selectedTabID: UUID?
        for (index, persisted) in session.tabs.enumerated() {
            let restoredTab: CenterTab
            switch persisted.kind {
            case .file:
                guard let path = persisted.path else { continue }
                let url = URL(fileURLWithPath: path).standardizedFileURL
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                let editor = EditorSession(url: url)
                editor.isWordWrapEnabled = persisted.isWordWrapEnabled
                restoredTab = CenterTab(
                    content: .file(editor),
                    fileDisposition: persisted.isPreview ? .preview : .permanent
                )
                if !persisted.isPreview { recentFiles.record(url) }
            case .terminal:
                let terminal = TerminalSession(number: nextNumber, workspacePath: workspacePath)
                terminal.controller.onCommandFinished = terminalCommandFinished
                nextNumber += 1
                restoredTab = CenterTab(
                    content: .terminal(terminal),
                    customTitle: persisted.title
                )
            }
            tabs.append(restoredTab)
            if index == session.selectedTabIndex { selectedTabID = restoredTab.id }
        }

        guard !tabs.isEmpty else {
            add()
            return
        }
        let selection = selectedTabID ?? tabs.last?.id
        selectedID = selection
        if let selection,
           case .terminal = tabs.first(where: { $0.id == selection })?.content {
            lastSelectedTerminalID = selection
        }
    }

    /// Installs a command-finished handler on every terminal controller,
    /// current and future. Used by the Gemma sidecar's Terminal Guardian.
    func setTerminalCommandFinishedHandler(_ handler: ((Int32) -> Void)?) {
        terminalCommandFinished = handler
        for tab in tabs {
            if case .terminal(let session) = tab.content {
                session.controller.onCommandFinished = handler
            }
        }
    }

    /// Returns the last `lines` rows of the selected terminal, or nil when the
    /// selected tab is not a terminal. Content is never logged.
    func selectedTerminalScrollback(lines: Int) -> String? {
        guard let selectedTab,
              case .terminal(let session) = selectedTab.content else { return nil }
        return session.controller.scrollbackSnapshot(lines: lines)
    }

    /// Context for the Gemma sidecar derived from the selected center tab.
    var selectedSidecarContext: GemmaSidecarTabContext? {
        guard let selectedTab else { return nil }
        switch selectedTab.content {
        case .terminal:
            return GemmaSidecarTabContext(
                kind: .terminal,
                title: selectedTab.title,
                status: "Running",
                systemImage: "terminal",
                filePath: nil,
                workingDirectory: workspacePath,
                gitDiffPath: nil,
                editorSelection: nil
            )
        case .file(let editor):
            return GemmaSidecarTabContext(
                kind: .file,
                title: selectedTab.title,
                status: fileStatus(editor.content),
                systemImage: "doc.text",
                filePath: editor.document.url.path,
                workingDirectory: nil,
                gitDiffPath: nil,
                editorSelection: editor.selectedText
            )
        case .gitDiff(let diff):
            return GemmaSidecarTabContext(
                kind: .gitDiff,
                title: selectedTab.title,
                status: gitDiffStatus(diff.state),
                systemImage: "doc.text.magnifyingglass",
                filePath: nil,
                workingDirectory: nil,
                gitDiffPath: diff.selection.change.path,
                editorSelection: nil
            )
        case .gemma(let model):
            return GemmaSidecarTabContext(
                kind: .gemma,
                title: selectedTab.title,
                status: gemmaStatus(model.status),
                systemImage: "sparkles",
                filePath: nil,
                workingDirectory: nil,
                gitDiffPath: nil,
                editorSelection: nil
            )
        }
    }

    fileprivate var visibleTabs: [CenterTab] {
        tabs
    }

    fileprivate var selectedTab: CenterTab? {
        tabs.first { $0.id == selectedID }
    }

    var selectedEditor: EditorSession? {
        guard let selectedTab,
              case .file(let editor) = selectedTab.content else { return nil }
        return editor
    }

    var terminalCount: Int {
        tabs.reduce(into: 0) { count, tab in
            if case .terminal = tab.content {
                count += 1
            }
        }
    }

    func runtimeDiagnosticsSnapshot(workspaceRoot: URL) -> RuntimeMainSnapshot {
        var workspace = RuntimeWorkspaceSnapshot(
            active: true,
            relativeRootName: workspaceRoot.lastPathComponent,
            tabCount: tabs.count
        )
        var editor = RuntimeEditorSnapshot()
        for tab in tabs {
            switch tab.content {
            case .terminal:
                workspace.terminalTabCount += 1
            case .file(let session):
                workspace.fileTabCount += 1
                workspace.loadedFileBytes += session.diagnosticLoadedBytes
                if session.diagnosticLoadedBytes > 0 { workspace.fileSessionCount += 1 }
                if tab.isPreview {
                    workspace.previewFileCount += 1
                } else {
                    workspace.permanentFileCount += 1
                }
                if workspace.fileTabs.count < RuntimeDiagnosticsService.fileMetricCapacity,
                   let relativePath = FileTreePathPolicy.relativePath(
                       of: session.document.url,
                       within: workspaceRoot
                   ) {
                    workspace.fileTabs.append(RuntimeFileTabMetric(
                        relativePath: relativePath,
                        loadedBytes: session.diagnosticLoadedBytes,
                        loadState: session.diagnosticLoadState,
                        isPreview: tab.isPreview
                    ))
                }
            case .gitDiff:
                workspace.gitDiffTabCount += 1
            case .gemma:
                workspace.gemmaTabCount += 1
            }
        }
        if let selectedTab {
            switch selectedTab.content {
            case .terminal:
                workspace.selectedTabKind = "terminal"
            case .file(let session):
                workspace.selectedTabKind = "file"
                workspace.selectedFileRelativePath = FileTreePathPolicy.relativePath(
                    of: session.document.url,
                    within: workspaceRoot
                )
                editor = session.runtimeEditorSnapshot()
                editor.selectedControllerID = session.runtimeControllerID
            case .gitDiff:
                workspace.selectedTabKind = "gitDiff"
            case .gemma:
                workspace.selectedTabKind = "gemma"
            }
        }
        return RuntimeMainSnapshot(workspace: workspace, editor: editor)
    }

    var openTerminalTabs: [OpenTerminalTab] {
        tabs.compactMap { tab in
            guard case .terminal(let session) = tab.content else { return nil }
            return OpenTerminalTab(
                id: tab.id,
                title: tab.title,
                controller: session.controller
            )
        }
    }

    @discardableResult
    func selectTerminal(id: UUID) -> Bool {
        guard let tab = tabs.first(where: { tab in
            guard tab.id == id, case .terminal = tab.content else { return false }
            return true
        }), case .terminal(let session) = tab.content else { return false }
        select(tab)
        Task { @MainActor [controller = session.controller] in
            await Task.yield()
            controller.requestFocus()
        }
        return true
    }

    var gemmaTabCount: Int {
        tabs.reduce(into: 0) { count, tab in
            if case .gemma = tab.content { count += 1 }
        }
    }

    var fileTabCount: Int {
        tabs.reduce(into: 0) { count, tab in
            if case .file = tab.content { count += 1 }
        }
    }

    var previewFileTabCount: Int {
        tabs.count(where: \.isPreview)
    }

    var previewFileURL: URL? {
        tabs.first(where: \.isPreview).flatMap { tab in
            guard case .file(let file) = tab.content else { return nil }
            return file.document.url
        }
    }

    var selectedFileURL: URL? {
        guard let selectedTab,
              case .file(let file) = selectedTab.content else { return nil }
        return file.document.url
    }

    var selectedFileDisposition: FileTabDisposition? {
        selectedTab?.fileDisposition
    }

    var gitDiffTabCount: Int {
        tabs.reduce(into: 0) { count, tab in
            if case .gitDiff = tab.content { count += 1 }
        }
    }

    var selectedGitDiffSelection: DiffSelection? {
        guard let selectedTab,
              case .gitDiff(let diff) = selectedTab.content else { return nil }
        return diff.selection
    }

    var isTerminalSelected: Bool {
        guard let selectedTab,
              case .terminal = selectedTab.content else { return false }
        return true
    }

    func pasteIntoSelectedTerminal(_ text: String) -> Bool {
        guard !text.isEmpty,
              let selectedTab,
              case .terminal(let session) = selectedTab.content else { return false }
        lastSelectedTerminalID = selectedTab.id
        session.controller.paste(text)
        return true
    }

    var canPasteSelectedEditorReference: Bool {
        guard let selectedEditor,
              selectedEditor.selectionReference(workspaceRootURL: workspaceRootURL) != nil else {
            return false
        }
        return preferredTerminalTab != nil
    }

    @discardableResult
    func pasteSelectedEditorReferenceIntoTerminal() -> Bool {
        guard let selectedEditor,
              let reference = selectedEditor.selectionReference(
                  workspaceRootURL: workspaceRootURL
              ),
              let terminalTab = preferredTerminalTab,
              case .terminal(let session) = terminalTab.content else { return false }
        select(terminalTab)
        session.controller.paste(reference)
        return true
    }

    var canCloseSelectedTab: Bool {
        guard let selectedTab else { return false }
        return canClose(selectedTab)
    }

    var canNavigateBack: Bool { fileNavigationHistory.canGoBack }
    var canNavigateForward: Bool { fileNavigationHistory.canGoForward }
    var canReopenClosedTab: Bool { fileNavigationHistory.canReopenClosed }

    var recentFileURLs: [URL] {
        recentFiles.urls
    }

    var selectedInspectorContext: TerminalTabInspectorContext? {
        guard let selectedTab else { return nil }

        switch selectedTab.content {
        case .terminal:
            return TerminalTabInspectorContext(
                kind: .terminal,
                title: selectedTab.title,
                systemImage: "terminal",
                status: "Running",
                details: [
                    TerminalTabInspectorDetail(
                        label: "Working directory",
                        value: workspacePath
                    ),
                    TerminalTabInspectorDetail(
                        label: "Session",
                        value: "Interactive shell"
                    )
                ],
                showsActivity: true
            )
        case .file(let editor):
            return TerminalTabInspectorContext(
                kind: .file,
                title: selectedTab.title,
                systemImage: "doc.text",
                status: fileStatus(editor.content),
                details: [
                    TerminalTabInspectorDetail(
                        label: "Path",
                        value: editor.document.url.path
                    ),
                    TerminalTabInspectorDetail(
                        label: "Type",
                        value: editor.document.url.pathExtension.isEmpty
                            ? "File"
                            : editor.document.url.pathExtension.uppercased()
                    ),
                    TerminalTabInspectorDetail(
                        label: "Word wrap",
                        value: editor.isWordWrapEnabled ? "On" : "Off"
                    )
                ],
                showsActivity: false
            )
        case .gitDiff(let diff):
            var details = [
                TerminalTabInspectorDetail(label: "Path", value: diff.selection.change.path),
                TerminalTabInspectorDetail(label: "Source", value: diff.selection.stateLabel),
                TerminalTabInspectorDetail(
                    label: "Change",
                    value: diff.selection.change.kind.rawValue.capitalized
                )
            ]
            if case .loaded(let document) = diff.state {
                details.append(
                    TerminalTabInspectorDetail(
                        label: "Delta",
                        value: "+\(document.additions) -\(document.deletions)"
                    )
                )
            }
            return TerminalTabInspectorContext(
                kind: .gitDiff,
                title: selectedTab.title,
                systemImage: "doc.text.magnifyingglass",
                status: gitDiffStatus(diff.state),
                details: details,
                showsActivity: false
            )
        case .gemma(let model):
            return TerminalTabInspectorContext(
                kind: .gemma,
                title: selectedTab.title,
                systemImage: "sparkles",
                status: gemmaStatus(model.status),
                details: [
                    TerminalTabInspectorDetail(label: "Model", value: "gemma4:cloud"),
                    TerminalTabInspectorDetail(
                        label: "Messages",
                        value: model.messages.count.formatted()
                    ),
                    TerminalTabInspectorDetail(
                        label: "Tool activity",
                        value: model.activities.count.formatted()
                    ),
                    TerminalTabInspectorDetail(label: "Access", value: "Read-only")
                ],
                showsActivity: model.isRunning
            )
        }
    }

    private func fileStatus(_ content: FileContent) -> String {
        switch content {
        case .loading: "Loading"
        case .text(let text): "\(text.split(whereSeparator: \Character.isNewline).count) lines"
        case .image: "Image preview"
        case .binary: "Binary"
        case .tooLarge: "Too large to preview"
        case .error: "Load failed"
        }
    }

    private func gitDiffStatus(_ state: GitDiffLoadState) -> String {
        switch state {
        case .loading: "Loading"
        case .loaded: "Ready"
        case .message: "No diff"
        case .failed: "Load failed"
        }
    }

    private func gemmaStatus(_ status: GemmaAgentStatus) -> String {
        switch status {
        case .idle: "Ready"
        case .running: "Running"
        case .completed: "Completed"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        }
    }

    func add() {
        let session = TerminalSession(number: nextNumber, workspacePath: workspacePath)
        session.controller.onCommandFinished = terminalCommandFinished
        let tab = CenterTab(content: .terminal(session))
        nextNumber += 1
        tabs.append(tab)
        select(tab)
    }

    func addAndRun(_ command: String) {
        guard !command.isEmpty else { return }
        add()
        _ = pasteIntoSelectedTerminal("\(command)\n")
    }

    // Runs a command in the selected terminal, or opens a new one when the
    // active tab is not a terminal. Used by the Watchtower command drop.
    @discardableResult
    func runCommand(_ command: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if isTerminalSelected {
            return pasteIntoSelectedTerminal("\(trimmed)\n")
        }
        addAndRun(trimmed)
        return true
    }

    func closeAll() {
        for tab in tabs {
            switch tab.content {
            case .terminal(let session):
                session.close()
            case .file(let file):
                file.close()
            case .gitDiff(let diff):
                diff.close()
            case .gemma(let model):
                model.close()
            }
        }
        tabs.removeAll(keepingCapacity: false)
        recentFiles.removeAll()
        fileNavigationHistory.clear()
        lastSelectedTerminalID = nil
        pendingTerminalCloseConfirmation = nil
        selectedID = nil
    }

    func openFile(_ url: URL) {
        openFile(url, disposition: .permanent)
    }

    func previewFile(_ url: URL) {
        openFile(url, disposition: .preview)
    }

    func promotePreview(for url: URL) {
        let standardizedURL = url.standardizedFileURL
        guard let index = tabs.firstIndex(where: { tab in
            guard tab.isPreview,
                  case .file(let file) = tab.content else { return false }
            return file.document.url == standardizedURL
        }) else { return }
        promotePreview(at: index)
    }

    func navigateBack() {
        guard let target = fileNavigationHistory.goBack() else { return }
        openFile(target.url, disposition: target.disposition, recordsNavigation: false)
    }

    func navigateForward() {
        guard let target = fileNavigationHistory.goForward() else { return }
        openFile(target.url, disposition: target.disposition, recordsNavigation: false)
    }

    func reopenClosedTab() {
        guard let target = fileNavigationHistory.reopenClosed() else { return }
        openFile(target.url, disposition: .permanent, recordsNavigation: false)
    }

    private func openFile(
        _ url: URL,
        disposition: FileTabDisposition,
        recordsNavigation: Bool = true
    ) {
        let standardizedURL = url.standardizedFileURL

        if let index = tabs.firstIndex(where: { tab in
            guard case .file(let file) = tab.content else { return false }
            return file.document.url == standardizedURL
        }) {
            let tab = tabs[index]
            guard case .file(let file) = tab.content else { return }
            if disposition == .permanent {
                if tab.isPreview {
                    promotePreview(at: index)
                } else {
                    recentFiles.record(standardizedURL)
                }
            }
            file.reload()
            selectedID = tab.id
            if recordsNavigation,
               let target = navigationTarget(for: tabs[index]) {
                fileNavigationHistory.record(target)
            }
            return
        }

        if disposition == .preview,
           let previewIndex = tabs.firstIndex(where: \.isPreview) {
            removeTab(at: previewIndex, recordsClosedFile: false)
        }

        let tab = CenterTab(
            content: .file(EditorSession(url: standardizedURL)),
            fileDisposition: disposition
        )
        tabs.append(tab)
        selectedID = tab.id
        if disposition == .permanent {
            recentFiles.record(standardizedURL)
        }
        if recordsNavigation,
           let target = navigationTarget(for: tab) {
            fileNavigationHistory.record(target)
        }
    }

    private func promotePreview(at index: Int) {
        let tab = tabs[index]
        guard tab.isPreview,
              case .file(let file) = tab.content else { return }
        tabs[index] = CenterTab(
            id: tab.id,
            content: tab.content,
            customTitle: tab.customTitle,
            fileDisposition: .permanent
        )
        recentFiles.record(file.document.url)
        fileNavigationHistory.promote(file.document.url)
        onSessionChange?()
    }

    func openGitDiff(_ selection: DiffSelection) {
        if let tab = tabs.first(where: { tab in
            guard case .gitDiff(let diff) = tab.content else { return false }
            return diff.selection == selection
        }) {
            guard case .gitDiff(let diff) = tab.content else { return }
            if diff.needsReload { diff.reload() }
            selectedID = tab.id
            return
        }

        let diff = GitDiffSession(
            selection: selection,
            workspacePath: workspacePath,
            cache: gitDiffCache
        )
        let tab = CenterTab(content: .gitDiff(diff))
        tabs.append(tab)
        selectedID = tab.id
    }

    func invalidateGitDiffs() {
        gitDiffCache.invalidateAll()
        for tab in tabs {
            guard case .gitDiff(let diff) = tab.content else { continue }
            diff.invalidate()
        }
    }

    func closeSelectedTab() {
        guard let selectedTab else { return }
        requestClose(selectedTab)
    }

    func confirmTerminalClose(id: UUID) {
        pendingTerminalCloseConfirmation = nil
        guard let tab = tabs.first(where: { $0.id == id }),
              case .terminal = tab.content else { return }
        close(tab)
    }

    func cancelTerminalClose() {
        pendingTerminalCloseConfirmation = nil
    }

    func closeFiles(atOrUnder url: URL) {
        let indexes = tabs.indices.filter { index in
            guard case .file(let file) = tabs[index].content else { return false }
            return FileTreePathPolicy.contains(file.document.url, within: url)
        }
        for index in indexes.reversed() {
            removeTab(at: index, recordsClosedFile: false)
        }
        recentFiles.removeItem(at: url)
        fileNavigationHistory.removeItem(at: url)
    }

    func openGemma(_ model: GemmaAgentModel) {
        if let tab = tabs.first(where: { tab in
            guard case .gemma(let existing) = tab.content else { return false }
            return existing === model
        }) {
            selectedID = tab.id
            return
        }
        let tab = CenterTab(content: .gemma(model))
        tabs.append(tab)
        selectedID = tab.id
    }

    fileprivate func select(_ tab: CenterTab) {
        selectedID = tab.id
        if case .terminal = tab.content {
            lastSelectedTerminalID = tab.id
        }
        if let target = navigationTarget(for: tab) {
            fileNavigationHistory.record(target)
        }
    }

    fileprivate func close(_ tab: CenterTab) {
        guard canClose(tab),
              let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        removeTab(at: index, recordsClosedFile: true)
    }

    fileprivate func requestClose(_ tab: CenterTab) {
        guard canClose(tab),
              tabs.contains(where: { $0.id == tab.id }) else { return }
        if case .terminal(let session) = tab.content,
           TerminalClosePolicy.requiresConfirmation(
               foregroundAgentName: session.controller.currentForegroundAgentName()
           ) {
            pendingTerminalCloseConfirmation = TerminalCloseConfirmation(
                id: tab.id,
                title: tab.title
            )
            return
        }
        close(tab)
    }

    fileprivate func canClose(_ tab: CenterTab) -> Bool {
        if case .terminal = tab.content, terminalCount == 1 {
            return false
        }
        return true
    }

    private func removeTab(at index: Int, recordsClosedFile: Bool) {
        let tab = tabs[index]
        if pendingTerminalCloseConfirmation?.id == tab.id {
            pendingTerminalCloseConfirmation = nil
        }
        if recordsClosedFile,
           let target = navigationTarget(for: tab) {
            fileNavigationHistory.recordClosed(target)
        }
        switch tab.content {
        case .terminal(let session):
            session.close()
        case .file(let file):
            file.close()
        case .gitDiff(let diff):
            diff.close()
        case .gemma(let model):
            model.close()
        }
        tabs.remove(at: index)
        if selectedID == tab.id {
            selectedID = tabs.indices.contains(index)
                ? tabs[index].id
                : tabs.last?.id
            if recordsClosedFile,
               let selectedTab,
               let target = navigationTarget(for: selectedTab) {
                fileNavigationHistory.record(target)
            }
        }
        repairLastSelectedTerminal()
        onSessionChange?()
    }

    private var workspaceRootURL: URL {
        URL(fileURLWithPath: workspacePath, isDirectory: true)
    }

    private var preferredTerminalTab: CenterTab? {
        if let lastSelectedTerminalID,
           let tab = tabs.first(where: { tab in
               guard tab.id == lastSelectedTerminalID,
                     case .terminal = tab.content else { return false }
               return true
           }) {
            return tab
        }
        return tabs.first { tab in
            if case .terminal = tab.content { return true }
            return false
        }
    }

    private func repairLastSelectedTerminal() {
        if let lastSelectedTerminalID,
           tabs.contains(where: { tab in
               guard tab.id == lastSelectedTerminalID,
                     case .terminal = tab.content else { return false }
               return true
           }) {
            return
        }
        if let selectedTab,
           case .terminal = selectedTab.content {
            lastSelectedTerminalID = selectedTab.id
            return
        }
        lastSelectedTerminalID = tabs.first(where: { tab in
            if case .terminal = tab.content { return true }
            return false
        })?.id
    }

    private func navigationTarget(for tab: CenterTab) -> FileNavigationTarget? {
        guard case .file(let file) = tab.content,
              let disposition = tab.fileDisposition else { return nil }
        return FileNavigationTarget(url: file.document.url, disposition: disposition)
    }

    fileprivate func renameTab(id: UUID, to title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty,
              let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs[index]
        tabs[index] = CenterTab(
            id: tab.id,
            content: tab.content,
            customTitle: title,
            fileDisposition: tab.fileDisposition
        )
        onSessionChange?()
    }

    fileprivate func moveTab(id: UUID, over destinationID: UUID) {
        guard id != destinationID,
              let sourceIndex = tabs.firstIndex(where: { $0.id == id }),
              let destinationIndex = tabs.firstIndex(where: { $0.id == destinationID }) else {
            return
        }
        tabs.move(
            fromOffsets: IndexSet(integer: sourceIndex),
            toOffset: destinationIndex > sourceIndex ? destinationIndex + 1 : destinationIndex
        )
        onSessionChange?()
    }

    isolated deinit {
        closeAll()
    }
}

private struct RenameActiveTabKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct ToggleWordWrapKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct InsertSelectionReferenceKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    @Entry var activeEditor: EditorSession?
    @Entry var renderedFilePreview: Binding<Bool>?

    var renameActiveTab: (() -> Void)? {
        get { self[RenameActiveTabKey.self] }
        set { self[RenameActiveTabKey.self] = newValue }
    }

    var toggleWordWrap: (() -> Void)? {
        get { self[ToggleWordWrapKey.self] }
        set { self[ToggleWordWrapKey.self] = newValue }
    }

    var insertSelectionReference: (() -> Void)? {
        get { self[InsertSelectionReferenceKey.self] }
        set { self[InsertSelectionReferenceKey.self] = newValue }
    }
}

struct AtelierTabCommands: Commands {
    @FocusedValue(\.activeEditor) private var activeEditor
    @FocusedValue(\.insertSelectionReference) private var insertSelectionReference
    @FocusedValue(\.renameActiveTab) private var renameActiveTab
    @FocusedValue(\.renderedFilePreview) private var renderedFilePreview
    @FocusedValue(\.toggleWordWrap) private var toggleWordWrap

    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Button("Insert Selection Reference into Terminal") {
                insertSelectionReference?()
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(insertSelectionReference == nil)

            Divider()

            Button("Find...") {
                activeEditor?.performFindAction(.showFindInterface)
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(!canFindInFile)

            Button("Find and Replace...") {
                activeEditor?.performFindAction(.showReplaceInterface)
            }
            .keyboardShortcut("f", modifiers: [.command, .option])
            .disabled(!canFindInFile)

            Button("Find Next") {
                activeEditor?.performFindAction(.nextMatch)
            }
            .keyboardShortcut("g", modifiers: .command)
            .disabled(!canFindInFile)

            Button("Find Previous") {
                activeEditor?.performFindAction(.previousMatch)
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .disabled(!canFindInFile)

            Button(commandETitle) {
                if let renderedFilePreview {
                    renderedFilePreview.wrappedValue.toggle()
                } else {
                    activeEditor?.performFindAction(.setSearchString)
                }
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(renderedFilePreview == nil && !canFindInFile)
        }

        CommandGroup(after: .toolbar) {
            Button("Rename Tab...") {
                renameActiveTab?()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(renameActiveTab == nil)

            Button("Toggle Word Wrap") {
                toggleWordWrap?()
            }
            .keyboardShortcut("z", modifiers: .option)
            .disabled(toggleWordWrap == nil)
        }
    }

    private var canFindInFile: Bool {
        activeEditor?.canFindInFile == true
    }

    private var commandETitle: String {
        guard let renderedFilePreview else { return "Use Selection for Find" }
        return renderedFilePreview.wrappedValue ? "Show Source" : "Show Preview"
    }
}

nonisolated enum TerminalWorkspaceActivationPolicy {
    static func isActive(workspaceIsActive: Bool, selectedID: UUID?, tabID: UUID) -> Bool {
        workspaceIsActive && selectedID == tabID
    }
}

struct TerminalTabs: View {
    @Bindable var model: TerminalTabsModel
    @Bindable var agentResponses: AgentResponsesModel
    let isWorkspaceActive: Bool
    let isAgentSidecarPresented: Bool
    let onOpenAgentSidecar: () -> Void
    let onCloseAgentSidecar: () -> Void
    @Environment(AtelierZoomModel.self) private var zoom
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var renameTargetID: UUID?
    @State private var tabFrames: [UUID: CGRect] = [:]
    @State private var draggedTabID: UUID?
    @State private var lastReorderTargetID: UUID?
    @State private var hoveredTabID: UUID?
    @State private var renderedPreviewTabIDs: Set<UUID> = []
    @State private var renderedSourceTabIDs: Set<UUID> = []
    @State private var agentResponseOverlayMode: AgentResponseOverlayMode = .full

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    ZStack(alignment: .topLeading) {
                        ForEach(model.visibleTabs) { tab in
                            if let frame = tabFrames[tab.id] {
                                RoundedRectangle(
                                    cornerRadius: AtelierTheme.rowRadius,
                                    style: .continuous
                                )
                                .fill(tabBackground(tab))
                                .frame(
                                    width: max(0, frame.width - 6),
                                    height: max(0, frame.height - 10)
                                )
                                .offset(x: frame.minX + 3, y: frame.minY + 5)
                            }
                        }

                        GlassEffectContainer(spacing: 0) {
                            if let selectedID = model.selectedID,
                               let frame = tabFrames[selectedID]?.insetBy(dx: 3, dy: 5) {
                                AtelierMovingGlassIndicator(
                                    frame: frame,
                                    tint: AtelierTheme.chromeSelection.opacity(0.5),
                                    fallbackFill: AtelierTheme.chromeSelection
                                )
                                .glassEffectTransition(.identity)
                            }
                        }

                        HStack(spacing: 0) {
                            ForEach(model.visibleTabs) { tab in
                                ZStack(alignment: .leading) {
                                    HStack(spacing: AtelierMetrics.spaceS) {
                                        Image(systemName: tab.systemImage)
                                            .atelierFont(size: AtelierTypography.caption)
                                        Text(tab.title)
                                            .atelierFont(
                                                size: AtelierTypography.label,
                                                weight: tab.isPreview ? .regular : .medium
                                            )
                                            .opacity(tab.isPreview ? 0.72 : 1)
                                            .lineLimit(1)
                                    }
                                    .padding(
                                        .leading,
                                        model.canClose(tab)
                                            ? AtelierMetrics.space2XL
                                            : AtelierMetrics.spaceM
                                    )
                                    .padding(.trailing, AtelierMetrics.spaceM)
                                    .frame(
                                        minWidth: AtelierMetrics.tabMinWidth,
                                        idealWidth: AtelierMetrics.tabIdealWidth,
                                        maxWidth: AtelierMetrics.tabMaxWidth
                                    )
                                    .frame(height: AtelierMetrics.tabBarHeight - 10)
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(true)
                                }
                                .foregroundStyle(
                                    model.selectedID == tab.id
                                        ? AtelierTheme.chromeSelectionInk
                                        : Color.secondary
                                )
                                .padding(.horizontal, 3)
                                .padding(.vertical, 5)
                                .overlay {
                                    Button {
                                        model.select(tab)
                                    } label: {
                                        Color.clear
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(tab.title)
                                    .accessibilityValue(tabAccessibilityValue(tab))
                                }
                                .overlay(alignment: .leading) {
                                    if model.canClose(tab) {
                                        TabCloseButton(help: tab.closeHelp) {
                                            model.requestClose(tab)
                                        }
                                        .padding(.leading, 3)
                                        .opacity(
                                            model.selectedID == tab.id || hoveredTabID == tab.id
                                                ? 1
                                                : 0
                                        )
                                    }
                                }
                                .contentShape(Rectangle())
                                .atelierPointerCursor()
                                .onHover { isHovering in
                                    hoveredTabID = isHovering ? tab.id : nil
                                }
                                .background {
                                    GeometryReader { proxy in
                                        Color.clear.preference(
                                            key: TabFramePreferenceKey.self,
                                            value: [tab.id: proxy.frame(in: .named("tabStrip"))]
                                        )
                                    }
                                }
                                .highPriorityGesture(
                                    DragGesture(
                                        minimumDistance: 6,
                                        coordinateSpace: .named("tabStrip")
                                    )
                                    .onChanged { value in
                                        reorderTab(tab.id, at: value.location)
                                    }
                                    .onEnded { _ in
                                        draggedTabID = nil
                                        lastReorderTargetID = nil
                                    }
                                )
                                .contextMenu {
                                    Button("Rename Tab...") {
                                        beginRename(tab.id)
                                    }
                                    if model.canClose(tab) {
                                        Divider()
                                        Button("Close Tab") {
                                            model.requestClose(tab)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .coordinateSpace(.named("tabStrip"))
                    .onPreferenceChange(TabFramePreferenceKey.self) { frames in
                        guard tabFrames != frames else { return }
                        Task { @MainActor in
                            guard tabFrames != frames else { return }
                            tabFrames = frames
                        }
                    }
                    .clipped()
                }
                .atelierScrollChrome(backgroundColor: AppKitThemeAdapter.chrome)

                HStack(spacing: AtelierMetrics.spaceXS) {
                    Button(action: toggleAgentResponseOverlay) {
                        HStack(spacing: AtelierMetrics.spaceXS) {
                            Image(systemName: "text.bubble")
                            Text("Response")
                            if agentResponses.unreadCount > 0 {
                                Circle()
                                    .fill(AtelierTheme.accent)
                                    .frame(width: 6, height: 6)
                            }
                        }
                        .atelierFont(size: AtelierTypography.caption, weight: .semibold)
                        .padding(.horizontal, AtelierMetrics.spaceS)
                        .frame(height: AtelierMetrics.controlHeight)
                        .contentShape(
                            RoundedRectangle(cornerRadius: AtelierTheme.controlRadius)
                        )
                    }
                    .buttonStyle(.plain)
                    .atelierPointerCursor()
                    .foregroundStyle(
                        isAgentSidecarPresented ? AtelierTheme.accent : Color.primary
                    )
                    .atelierGlassControl(isSelected: isAgentSidecarPresented)
                    .accessibilityLabel(
                        isAgentSidecarPresented
                            ? "Close agent response overlay"
                            : "Open agent response overlay"
                    )
                    .accessibilityValue("\(agentResponses.unreadCount) unread")
                    .help(
                        isAgentSidecarPresented
                            ? "Close Agent Responses"
                            : "Open Agent Responses"
                    )

                    if let editor = model.selectedEditor {
                        if FilePreviewPolicy.kind(for: editor.document.url) != nil,
                           let renderedFilePreviewBinding {
                            let showsPreview = renderedFilePreviewBinding.wrappedValue
                            Button {
                                renderedFilePreviewBinding.wrappedValue = !showsPreview
                            } label: {
                                Image(
                                    systemName: showsPreview
                                        ? "chevron.left.forwardslash.chevron.right"
                                        : "eye"
                                )
                            }
                            .buttonStyle(AtelierLuminareIconButtonStyle())
                            .help(showsPreview ? "Show Source" : "Show Preview")
                            .accessibilityLabel(showsPreview ? "Show Source" : "Show Preview")
                            .accessibilityValue(showsPreview ? "Preview" : "Source")
                        }

                        if !isRenderedPreviewVisible {
                            Button {
                                editor.toggleWordWrap()
                            } label: {
                                Image(
                                    systemName: editor.isWordWrapEnabled
                                        ? "text.word.spacing"
                                        : "arrow.left.and.right"
                                )
                            }
                            .buttonStyle(AtelierLuminareIconButtonStyle())
                            .help(
                                editor.isWordWrapEnabled
                                    ? "Disable Word Wrap"
                                    : "Enable Word Wrap"
                            )
                            .accessibilityLabel(
                                editor.isWordWrapEnabled
                                    ? "Disable Word Wrap"
                                    : "Enable Word Wrap"
                            )
                        }
                    }

                    Button {
                        model.add()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(AtelierLuminareIconButtonStyle())
                    .atelierNewTerminalEffect(sessionCount: model.terminalCount)
                    .accessibilityLabel("New terminal")
                    .help("New terminal")
                }
                .padding(.horizontal, AtelierMetrics.spaceXS)
            }
            .frame(height: AtelierMetrics.tabBarHeight)
            .background {
                AtelierChromeBackground()
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(AtelierTheme.border)
                    .frame(height: AtelierTheme.strokeHairline)
            }

            ZStack {
                ForEach(model.visibleTabs) { tab in
                    switch tab.content {
                    case .terminal(let session):
                        let isActive = TerminalWorkspaceActivationPolicy.isActive(
                            workspaceIsActive: isWorkspaceActive,
                            selectedID: model.selectedID,
                            tabID: tab.id
                        )
                        TerminalView(
                            controller: session.controller,
                            scale: zoom.contentScale,
                            isActive: isActive
                        )
                        .id(tab.id)
                        .background(AtelierTheme.editor)
                        .dropDestination(for: WatchtowerCommandDrop.self) { drops, _ in
                            guard let drop = drops.first else { return false }
                            return model.runCommand(drop.command)
                        }
                        .opacity(isActive ? 1 : 0)
                        .allowsHitTesting(isActive)
                        .accessibilityHidden(!isActive)
                        .zIndex(isActive ? 1 : 0)
                    case .file(let file):
                        let isActive = isWorkspaceActive && model.selectedID == tab.id
                        FileTabView(
                            file: file,
                            isActive: isActive,
                            showsPreview: showsRenderedPreview(
                                tabID: tab.id,
                                fileURL: file.document.url
                            )
                        ) {
                            model.promotePreview(for: file.document.url)
                        }
                        .id(tab.id)
                        .background(AtelierTheme.editor)
                        .environment(\.atelierZoomScale, zoom.contentScale)
                        .opacity(isActive ? 1 : 0)
                        .allowsHitTesting(isActive)
                        .disabled(!isActive)
                        .accessibilityHidden(!isActive)
                        .zIndex(isActive ? 1 : 0)
                    case .gitDiff, .gemma:
                        EmptyView()
                    }
                }

                if let tab = model.selectedTab {
                    switch tab.content {
                    case .terminal, .file:
                        EmptyView()
                    case .gitDiff(let diff):
                        GitDiffTabView(session: diff)
                            .id(tab.id)
                            .environment(\.atelierZoomScale, zoom.contentScale)
                    case .gemma(let agent):
                        GemmaAgentView(
                            model: agent,
                            workspaceRoot: URL(
                                fileURLWithPath: model.workspacePath,
                                isDirectory: true
                            ),
                            onOpenFile: model.openFile
                        )
                        .id(tab.id)
                        .environment(\.atelierZoomScale, zoom.contentScale)
                    }
                } else {
                    AtelierEmptyState(
                        systemImage: "rectangle.stack",
                        title: "No Open Tabs",
                        message: "Open a file or add a terminal tab."
                    )
                }
            }
            .overlay(alignment: .trailing) {
                if isAgentSidecarPresented {
                    AgentResponseOverlay(
                        model: agentResponses,
                        mode: agentResponseOverlayMode,
                        onToggleMode: toggleAgentResponseOverlayMode,
                        onClose: onCloseAgentSidecar
                    )
                    .transition(
                        reduceMotion
                            ? .identity
                            : .move(edge: .trailing).combined(with: .opacity)
                    )
                }
            }
        }
        .focusedSceneValue(\.activeEditor, activeEditorForCommands)
        .focusedSceneValue(\.insertSelectionReference, insertSelectionReferenceAction)
        .focusedSceneValue(\.renderedFilePreview, renderedFilePreviewBinding)
        .focusedSceneValue(\.renameActiveTab) {
            guard let selectedID = model.selectedID else { return }
            beginRename(selectedID)
        }
        .focusedSceneValue(\.toggleWordWrap, toggleWordWrapAction)
        .alert(
            "Close Running Terminal?",
            isPresented: terminalCloseAlertPresented,
            presenting: model.pendingTerminalCloseConfirmation
        ) { confirmation in
            Button("Cancel", role: .cancel) {
                model.cancelTerminalClose()
            }
            Button("Close Terminal", role: .destructive) {
                model.confirmTerminalClose(id: confirmation.id)
            }
            .keyboardShortcut(.defaultAction)
        } message: { confirmation in
            Text("\(confirmation.title) is still running. Closing it will stop its process.")
        }
        .sheet(isPresented: renameSheetPresented) {
            TabRenameSheet(currentTitle: renameTargetTitle) { title in
                guard let renameTargetID else { return }
                model.renameTab(id: renameTargetID, to: title)
                self.renameTargetID = nil
            } onCancel: {
                renameTargetID = nil
            }
        }
        .onChange(of: model.visibleTabs.map(\.id)) { _, visibleIDs in
            renderedPreviewTabIDs.formIntersection(visibleIDs)
            renderedSourceTabIDs.formIntersection(visibleIDs)
        }
    }

    private var isRenderedPreviewVisible: Bool {
        guard let selectedID = model.selectedID,
              let editor = model.selectedEditor else { return false }
        return showsRenderedPreview(tabID: selectedID, fileURL: editor.document.url)
    }

    private func showsRenderedPreview(tabID: UUID, fileURL: URL) -> Bool {
        if renderedSourceTabIDs.contains(tabID) { return false }
        if renderedPreviewTabIDs.contains(tabID) { return true }
        return FilePreviewPolicy.showsPreviewByDefault(for: fileURL)
    }

    private var renderedFilePreviewBinding: Binding<Bool>? {
        guard isWorkspaceActive,
              let selectedID = model.selectedID,
              let editor = model.selectedEditor,
              FilePreviewPolicy.kind(for: editor.document.url) != nil else { return nil }
        let fileURL = editor.document.url
        return Binding(
            get: {
                showsRenderedPreview(tabID: selectedID, fileURL: fileURL)
            },
            set: { showsPreview in
                if showsPreview {
                    renderedSourceTabIDs.remove(selectedID)
                    renderedPreviewTabIDs.insert(selectedID)
                } else {
                    renderedPreviewTabIDs.remove(selectedID)
                    renderedSourceTabIDs.insert(selectedID)
                }
            }
        )
    }

    private var activeEditorForCommands: EditorSession? {
        isRenderedPreviewVisible ? nil : model.selectedEditor
    }

    private var renameSheetPresented: Binding<Bool> {
        Binding(
            get: { renameTargetID != nil },
            set: { isPresented in
                if !isPresented { renameTargetID = nil }
            }
        )
    }

    private var toggleWordWrapAction: (() -> Void)? {
        guard let editor = activeEditorForCommands else { return nil }
        return { editor.toggleWordWrap() }
    }

    private var insertSelectionReferenceAction: (() -> Void)? {
        guard !isRenderedPreviewVisible else { return nil }
        guard model.canPasteSelectedEditorReference else { return nil }
        return { model.pasteSelectedEditorReferenceIntoTerminal() }
    }

    private var terminalCloseAlertPresented: Binding<Bool> {
        Binding(
            get: { model.pendingTerminalCloseConfirmation != nil },
            set: { isPresented in
                if !isPresented {
                    model.cancelTerminalClose()
                }
            }
        )
    }

    private var renameTargetTitle: String {
        guard let renameTargetID,
              let tab = model.visibleTabs.first(where: { $0.id == renameTargetID }) else {
            return "Tab name"
        }
        return tab.title
    }

    private func toggleAgentResponseOverlay() {
        if isAgentSidecarPresented {
            onCloseAgentSidecar()
        } else {
            agentResponseOverlayMode = .full
            onOpenAgentSidecar()
        }
    }

    private func toggleAgentResponseOverlayMode() {
        withAnimation(reduceMotion ? nil : AtelierMotionTokens.panel) {
            agentResponseOverlayMode = agentResponseOverlayMode == .full ? .half : .full
        }
    }

    private func tabBackground(_ tab: CenterTab) -> Color {
        if draggedTabID == tab.id {
            return AtelierTheme.controlFill(for: .pressed)
        }
        if model.selectedID == tab.id {
            return .clear
        }
        if hoveredTabID == tab.id {
            return AtelierTheme.controlFill(for: .hovered)
        }
        return AtelierTheme.tabInactive
    }

    private func tabAccessibilityValue(_ tab: CenterTab) -> String {
        let selection = model.selectedID == tab.id ? "Selected" : "Not selected"
        return tab.isPreview ? "\(selection), Preview" : selection
    }

    private func beginRename(_ id: UUID) {
        guard model.visibleTabs.contains(where: { $0.id == id }) else { return }
        renameTargetID = id
    }

    private func reorderTab(_ id: UUID, at location: CGPoint) {
        if draggedTabID != id {
            draggedTabID = id
            lastReorderTargetID = nil
        }
        guard let targetID = tabFrames.first(where: {
            $0.key != id && $0.value.contains(location)
        })?.key,
              targetID != lastReorderTargetID else { return }
        lastReorderTargetID = targetID
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
            model.moveTab(id: id, over: targetID)
        }
    }
}

private struct AgentResponseOverlay: View {
    @Bindable var model: AgentResponsesModel
    let mode: AgentResponseOverlayMode
    let onToggleMode: () -> Void
    let onClose: () -> Void

    @Environment(AtelierZoomModel.self) private var zoom

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                AgentResponsesView(
                    model: model,
                    onClose: onClose,
                    isFullWidth: mode == .full,
                    onToggleWidth: onToggleMode
                )
                .frame(
                    width: AgentSidecarLayoutPolicy.width(
                        availableWidth: proxy.size.width,
                        mode: mode
                    )
                )
                .frame(maxHeight: .infinity)
                .environment(\.atelierZoomScale, zoom.contentScale)
                .atelierOverlayPanel(edge: .trailing)
                .onExitCommand(perform: onClose)
            }
        }
    }
}

private struct TabCloseButton: View {
    let help: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .atelierFont(size: AtelierMetrics.smallIconSize, weight: .semibold)
                .frame(
                    width: AtelierMetrics.regularIconSize,
                    height: AtelierMetrics.regularIconSize
                )
                .background {
                    RoundedRectangle(cornerRadius: AtelierTheme.rowRadius, style: .continuous)
                        .fill(
                            AtelierTheme.controlFill(for: isHovering ? .hovered : .normal)
                        )
                }
                .frame(
                    width: AtelierMetrics.iconButtonSize,
                    height: AtelierMetrics.tabBarHeight - 10
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .onHover { isHovering = $0 }
        .accessibilityLabel(help)
        .help(help)
    }
}

private struct FileTabView: View {
    let file: EditorSession
    let isActive: Bool
    let showsPreview: Bool
    let onEdit: () -> Void

    @ViewBuilder
    var body: some View {
        if case .image(let data) = file.content {
            ImageViewer(data: data, name: file.document.displayName)
        } else if let previewKind = FilePreviewPolicy.kind(for: file.document.url) {
            ZStack {
                FileViewer(
                    content: file.content,
                    fileURL: file.document.url,
                    isActive: isActive && !showsPreview,
                    isWordWrapEnabled: file.isWordWrapEnabled,
                    surfaceOwner: file,
                    onEdit: onEdit
                )
                .opacity(showsPreview ? 0 : 1)
                .allowsHitTesting(!showsPreview)
                .accessibilityHidden(showsPreview)
                .zIndex(0)

                FileRenderedPreview(
                    kind: previewKind,
                    content: file.content,
                    fileURL: file.document.url,
                    isActive: isActive && showsPreview
                )
                .opacity(showsPreview ? 1 : 0)
                .allowsHitTesting(showsPreview)
                .accessibilityHidden(!showsPreview)
                .zIndex(1)
            }
        } else {
            FileViewer(
                content: file.content,
                fileURL: file.document.url,
                isActive: isActive,
                isWordWrapEnabled: file.isWordWrapEnabled,
                surfaceOwner: file,
                onEdit: onEdit
            )
        }
    }
}

private struct TabRenameSheet: View {
    let currentTitle: String
    let onRename: (String) -> Void
    let onCancel: () -> Void

    @State private var title = ""
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AtelierMetrics.spaceL) {
            Text("Rename Tab")
                .atelierFont(size: AtelierTypography.headline, weight: .semibold)

            TextField("Tab name", text: $title, prompt: Text(currentTitle))
                .textFieldStyle(.plain)
                .atelierFont(size: AtelierTypography.body)
                .focused($isTitleFocused)
                .padding(.horizontal, AtelierMetrics.spaceS)
                .frame(height: AtelierMetrics.fieldHeight)
                .atelierField(isFocused: isTitleFocused)
                .onSubmit(submit)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(AtelierGhostButtonStyle())
                Button("Rename", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(cleanTitle.isEmpty)
                    .buttonStyle(AtelierLuminarePrimaryButtonStyle())
            }
        }
        .padding(AtelierMetrics.spaceXL)
        .frame(width: AtelierMetrics.dialogWidth)
        .background(AtelierTheme.canvas)
        .onAppear {
            Task { @MainActor in
                isTitleFocused = true
            }
        }
    }

    private var cleanTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submit() {
        guard !cleanTitle.isEmpty else { return }
        onRename(cleanTitle)
    }
}

private struct TabFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
