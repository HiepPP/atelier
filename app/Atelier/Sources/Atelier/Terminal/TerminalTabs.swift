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

nonisolated enum AgentSidecarLayoutPolicy {
    static let width: CGFloat = 360
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
    var selectedID: UUID?

    fileprivate let workspacePath: String
    private var nextNumber = 1

    init(workspacePath: String) {
        self.workspacePath = workspacePath
        add()
    }

    fileprivate var visibleTabs: [CenterTab] {
        tabs
    }

    fileprivate var selectedTab: CenterTab? {
        tabs.first { $0.id == selectedID }
    }

    fileprivate var selectedEditor: EditorSession? {
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
        let tab = CenterTab(content: .terminal(session))
        nextNumber += 1
        tabs.append(tab)
        selectedID = tab.id
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

        let diff = GitDiffSession(selection: selection, workspacePath: workspacePath)
        let tab = CenterTab(content: .gitDiff(diff))
        tabs.append(tab)
        selectedID = tab.id
    }

    func invalidateGitDiffs() {
        for tab in tabs {
            guard case .gitDiff(let diff) = tab.content else { continue }
            diff.invalidate()
        }
    }

    func closeSelectedTab() {
        guard let selectedTab else { return }
        close(selectedTab)
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
        if let target = navigationTarget(for: tab) {
            fileNavigationHistory.record(target)
        }
    }

    fileprivate func canClose(_ tab: CenterTab) -> Bool {
        // The last terminal must always stay open.
        if case .terminal = tab.content, terminalCount == 1 { return false }
        return true
    }

    fileprivate func close(_ tab: CenterTab) {
        guard canClose(tab),
              let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        removeTab(at: index, recordsClosedFile: true)
    }

    private func removeTab(at index: Int, recordsClosedFile: Bool) {
        let tab = tabs[index]
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

private struct CloseActiveTabKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    @Entry var activeEditor: EditorSession?

    var renameActiveTab: (() -> Void)? {
        get { self[RenameActiveTabKey.self] }
        set { self[RenameActiveTabKey.self] = newValue }
    }

    var toggleWordWrap: (() -> Void)? {
        get { self[ToggleWordWrapKey.self] }
        set { self[ToggleWordWrapKey.self] = newValue }
    }

    var closeActiveTab: (() -> Void)? {
        get { self[CloseActiveTabKey.self] }
        set { self[CloseActiveTabKey.self] = newValue }
    }
}

struct AtelierTabCommands: Commands {
    @FocusedValue(\.activeEditor) private var activeEditor
    @FocusedValue(\.renameActiveTab) private var renameActiveTab
    @FocusedValue(\.toggleWordWrap) private var toggleWordWrap
    @FocusedValue(\.closeActiveTab) private var closeActiveTab

    var body: some Commands {
        CommandGroup(after: .pasteboard) {
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

            Button("Use Selection for Find") {
                activeEditor?.performFindAction(.setSearchString)
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(!canFindInFile)
        }

        CommandGroup(after: .toolbar) {
            Button("Close Tab") {
                closeActiveTab?()
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(closeActiveTab == nil)

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
}

struct TerminalTabs: View {
    @Bindable var model: TerminalTabsModel
    @Bindable var agentResponses: AgentResponsesModel
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

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(model.visibleTabs) { tab in
                            ZStack(alignment: .leading) {
                                Button {
                                    withAnimation(
                                        reduceMotion
                                            ? nil
                                            : .spring(response: 0.28, dampingFraction: 0.84)
                                    ) {
                                        model.select(tab)
                                    }
                                } label: {
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
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityValue(
                                    tabAccessibilityValue(tab)
                                )

                                if model.canClose(tab) {
                                    TabCloseButton(help: tab.closeHelp) {
                                        model.close(tab)
                                    }
                                    .opacity(
                                        model.selectedID == tab.id || hoveredTabID == tab.id
                                            ? 1
                                            : 0
                                    )
                                }
                            }
                            .foregroundStyle(
                                model.selectedID == tab.id
                                    ? AtelierTheme.chromeSelectionInk
                                    : Color.secondary
                            )
                            .background(
                                tabBackground(tab),
                                in: RoundedRectangle(
                                    cornerRadius: AtelierTheme.rowRadius,
                                    style: .continuous
                                )
                            )
                            .atelierSelectionGlass(
                                isSelected: model.selectedID == tab.id,
                                tint: AtelierTheme.chromeSelection.opacity(0.5),
                                fallbackFill: AtelierTheme.chromeSelection,
                                in: RoundedRectangle(
                                    cornerRadius: AtelierTheme.rowRadius,
                                    style: .continuous
                                )
                            )
                            .padding(.horizontal, 3)
                            .padding(.vertical, 5)
                            .overlay {
                                PointingHandCursorRegion()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                            .contentShape(Rectangle())
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
                                        model.close(tab)
                                    }
                                }
                            }
                        }
                    }
                    .coordinateSpace(name: "tabStrip")
                    .onPreferenceChange(TabFramePreferenceKey.self) { tabFrames = $0 }
                }
                .atelierScrollChrome(backgroundColor: AppKitThemeAdapter.chrome)

                HStack(spacing: AtelierMetrics.spaceXS) {
                    if model.isTerminalSelected {
                        Button {
                            if isAgentSidecarPresented {
                                onCloseAgentSidecar()
                            } else {
                                onOpenAgentSidecar()
                            }
                        } label: {
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
                                ? "Close agent response sidecar"
                                : "Open agent response sidecar"
                        )
                        .accessibilityValue("\(agentResponses.unreadCount) unread")
                        .help(
                            isAgentSidecarPresented
                                ? "Close Agent Responses"
                                : "Open Agent Responses"
                        )
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

                    if let editor = model.selectedEditor {
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
                        .help(editor.isWordWrapEnabled ? "Disable Word Wrap" : "Enable Word Wrap")
                        .accessibilityLabel(
                            editor.isWordWrapEnabled ? "Disable Word Wrap" : "Enable Word Wrap"
                        )
                    }
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
                    if case .terminal(let session) = tab.content {
                        let isActive = model.selectedID == tab.id
                        TerminalAgentSidecar(
                            session: session,
                            tabID: tab.id,
                            agentResponses: agentResponses,
                            isPresented: isAgentSidecarPresented,
                            isActive: isActive,
                            onClose: onCloseAgentSidecar
                        )
                        .opacity(isActive ? 1 : 0)
                        .allowsHitTesting(isActive)
                        .accessibilityHidden(!isActive)
                        .zIndex(isActive ? 1 : 0)
                    }
                }

                if let tab = model.selectedTab {
                    switch tab.content {
                    case .terminal:
                        EmptyView()
                    case .file(let file):
                        FileTabView(file: file) {
                            model.promotePreview(for: file.document.url)
                        }
                            .id(tab.id)
                            .background(AtelierTheme.editor)
                            .environment(\.atelierZoomScale, zoom.contentScale)
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
        }
        .focusedSceneValue(\.activeEditor, model.selectedEditor)
        .focusedSceneValue(\.renameActiveTab) {
            guard let selectedID = model.selectedID else { return }
            beginRename(selectedID)
        }
        .focusedSceneValue(\.toggleWordWrap, toggleWordWrapAction)
        .focusedSceneValue(\.closeActiveTab, closeActiveTabAction)
        .sheet(isPresented: renameSheetPresented) {
            TabRenameSheet(currentTitle: renameTargetTitle) { title in
                guard let renameTargetID else { return }
                model.renameTab(id: renameTargetID, to: title)
                self.renameTargetID = nil
            } onCancel: {
                renameTargetID = nil
            }
        }
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
        guard let editor = model.selectedEditor else { return nil }
        return { editor.toggleWordWrap() }
    }

    private var closeActiveTabAction: (() -> Void)? {
        guard let tab = model.selectedTab, model.canClose(tab) else { return nil }
        return { model.close(tab) }
    }

    private var renameTargetTitle: String {
        guard let renameTargetID,
              let tab = model.visibleTabs.first(where: { $0.id == renameTargetID }) else {
            return "Tab name"
        }
        return tab.title
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

private struct TerminalAgentSidecar: View {
    let session: TerminalSession
    let tabID: UUID
    @Bindable var agentResponses: AgentResponsesModel
    let isPresented: Bool
    let isActive: Bool
    let onClose: () -> Void

    @Environment(AtelierZoomModel.self) private var zoom

    var body: some View {
        terminal
            .overlay(alignment: .trailing) {
                if isPresented {
                    sidecar
                        .frame(width: AgentSidecarLayoutPolicy.width)
                        .atelierOverlayPanel(edge: .trailing)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .id(tabID)
            .background(AtelierTheme.editor)
    }

    private var terminal: some View {
        TerminalView(
            controller: session.controller,
            scale: zoom.contentScale,
            isActive: isActive
        )
        .background(AtelierTheme.editor)
    }

    private var sidecar: some View {
        AgentResponsesView(
            model: agentResponses,
            onClose: onClose
        )
        .frame(maxHeight: .infinity)
        .environment(\.atelierZoomScale, zoom.contentScale)
        .onExitCommand(perform: onClose)
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
    let onEdit: () -> Void

    @ViewBuilder
    var body: some View {
        if case .image(let data) = file.content {
            ImageViewer(data: data, name: file.document.displayName)
        } else {
            FileViewer(
                content: file.content,
                fileURL: file.document.url,
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

private struct PointingHandCursorRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        PointingHandCursorView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.window?.invalidateCursorRects(for: nsView)
    }
}

private final class PointingHandCursorView: NSView {
    private var trackingArea: NSTrackingArea?

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.invalidateCursorRects(for: self)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        window?.invalidateCursorRects(for: self)
    }
}
