import AppKit
import Observation
import SwiftUI

nonisolated enum AgentSidecarPresentation: Equatable, Sendable {
    case split
    case overlay
}

nonisolated enum AgentSidecarLayoutPolicy {
    static let splitBreakpoint: CGFloat = 900
    static let minimumWidth: CGFloat = 300
    static let maximumWidth: CGFloat = 480
    static let minimumTerminalWidth: CGFloat = 480

    static func presentation(containerWidth: CGFloat) -> AgentSidecarPresentation {
        containerWidth >= splitBreakpoint ? .split : .overlay
    }

    static func width(containerWidth: CGFloat) -> CGFloat {
        let ratio = presentation(containerWidth: containerWidth) == .split ? 0.32 : 0.46
        return min(maximumWidth, max(minimumWidth, (containerWidth * ratio).rounded()))
    }
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

    init(id: UUID = UUID(), content: CenterTabContent, customTitle: String? = nil) {
        self.id = id
        self.content = content
        self.customTitle = customTitle
    }

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
        selectedID = nil
    }

    func openFile(_ url: URL) {
        let standardizedURL = url.standardizedFileURL

        if let tab = tabs.first(where: { tab in
            guard case .file(let file) = tab.content else { return false }
            return file.document.url == standardizedURL
        }) {
            guard case .file(let file) = tab.content else { return }
            file.reload()
            selectedID = tab.id
            return
        }

        let tab = CenterTab(content: .file(EditorSession(url: standardizedURL)))
        tabs.append(tab)
        selectedID = tab.id
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
    }

    fileprivate func canClose(_ tab: CenterTab) -> Bool {
        // The last terminal must always stay open.
        if case .terminal = tab.content, terminalCount == 1 { return false }
        return true
    }

    fileprivate func close(_ tab: CenterTab) {
        guard canClose(tab),
              let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
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
        }
    }

    fileprivate func renameTab(id: UUID, to title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty,
              let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs[index]
        tabs[index] = CenterTab(id: tab.id, content: tab.content, customTitle: title)
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

extension FocusedValues {
    var renameActiveTab: (() -> Void)? {
        get { self[RenameActiveTabKey.self] }
        set { self[RenameActiveTabKey.self] = newValue }
    }

    var toggleWordWrap: (() -> Void)? {
        get { self[ToggleWordWrapKey.self] }
        set { self[ToggleWordWrapKey.self] = newValue }
    }
}

struct AtelierTabCommands: Commands {
    @FocusedValue(\.renameActiveTab) private var renameActiveTab
    @FocusedValue(\.toggleWordWrap) private var toggleWordWrap

    var body: some Commands {
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
                                                weight: .medium
                                            )
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
                                    .frame(height: AtelierMetrics.tabBarHeight)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityValue(
                                    model.selectedID == tab.id ? "Selected" : "Not selected"
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
                                model.selectedID == tab.id ? Color.primary : Color.secondary
                            )
                            .background(tabBackground(tab))
                            .overlay(alignment: .top) {
                                if model.selectedID == tab.id {
                                    Rectangle()
                                        .fill(AtelierTheme.accent)
                                        .frame(height: 2)
                                }
                            }
                            .overlay(alignment: .trailing) {
                                Rectangle()
                                    .fill(AtelierTheme.border)
                                    .frame(width: AtelierTheme.strokeHairline)
                            }
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
                            }
                        }
                    }
                    .coordinateSpace(name: "tabStrip")
                    .onPreferenceChange(TabFramePreferenceKey.self) { tabFrames = $0 }
                }
                .atelierScrollChrome(backgroundColor: AppKitThemeAdapter.chrome)

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
                    .foregroundStyle(
                        isAgentSidecarPresented ? AtelierTheme.accent : Color.primary
                    )
                    .glassEffect(
                        .regular
                            .tint(
                                isAgentSidecarPresented
                                    ? AtelierTheme.accent.opacity(0.16)
                                    : nil
                            )
                            .interactive(),
                        in: RoundedRectangle(
                            cornerRadius: AtelierTheme.controlRadius,
                            style: .continuous
                        )
                    )
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
            .padding(.trailing, AtelierMetrics.spaceXS)
            .frame(height: AtelierMetrics.tabBarHeight)
            .background(AtelierTheme.chrome)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(AtelierTheme.border)
                    .frame(height: AtelierTheme.strokeHairline)
            }

            if let tab = model.selectedTab {
                switch tab.content {
                case .terminal(let session):
                    TerminalAgentSidecar(
                        session: session,
                        tabID: tab.id,
                        agentResponses: agentResponses,
                        isPresented: isAgentSidecarPresented,
                        onClose: onCloseAgentSidecar
                    )
                case .file(let file):
                    FileTabView(file: file)
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
                        workspaceRoot: URL(fileURLWithPath: model.workspacePath, isDirectory: true),
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
        .focusedSceneValue(\.renameActiveTab) {
            guard let selectedID = model.selectedID else { return }
            beginRename(selectedID)
        }
        .focusedSceneValue(\.toggleWordWrap, toggleWordWrapAction)
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
            return AtelierTheme.controlFill(for: .selected)
        }
        if hoveredTabID == tab.id {
            return AtelierTheme.controlFill(for: .hovered)
        }
        return AtelierTheme.tabInactive
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
    let onClose: () -> Void

    @Environment(AtelierZoomModel.self) private var zoom

    var body: some View {
        GeometryReader { geometry in
            let presentation = AgentSidecarLayoutPolicy.presentation(
                containerWidth: geometry.size.width
            )
            let sidecarWidth = AgentSidecarLayoutPolicy.width(
                containerWidth: geometry.size.width
            )

            switch presentation {
            case .split:
                if isPresented {
                    HSplitView {
                        terminal
                            .frame(minWidth: AgentSidecarLayoutPolicy.minimumTerminalWidth)
                        sidecar
                            .frame(
                                minWidth: AgentSidecarLayoutPolicy.minimumWidth,
                                idealWidth: sidecarWidth,
                                maxWidth: AgentSidecarLayoutPolicy.maximumWidth
                            )
                    }
                    .atelierSplitViewChrome()
                } else {
                    terminal
                }
            case .overlay:
                terminal
                    .overlay(alignment: .trailing) {
                        if isPresented {
                            sidecar
                                .frame(width: sidecarWidth)
                                .atelierOverlayPanel(edge: .trailing)
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
            }
        }
        .id(tabID)
        .background(AtelierTheme.editor)
    }

    private var terminal: some View {
        TerminalView(
            controller: session.controller,
            scale: zoom.contentScale
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
                .frame(width: AtelierMetrics.iconButtonSize, height: AtelierMetrics.tabBarHeight)
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

    @ViewBuilder
    var body: some View {
        if case .image(let data) = file.content {
            ImageViewer(data: data, name: file.document.displayName)
        } else {
            FileViewer(
                content: file.content,
                fileURL: file.document.url,
                isWordWrapEnabled: file.isWordWrapEnabled
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
