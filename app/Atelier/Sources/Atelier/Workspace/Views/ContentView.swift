import AppKit
import SwiftUI

nonisolated enum WorkspaceLayoutMode: Equatable, Sendable {
    case compact
    case standard
    case wide

    var docksSidebar: Bool { self != .compact }
    var supportsInspector: Bool { self != .compact }
    var showsInspectorByDefault: Bool { self == .wide }
    var keepsSidebarWithInspector: Bool { self == .wide }
}

nonisolated enum WorkspaceSidebarTab: String, CaseIterable, Codable, Identifiable, Sendable {
    case explorer = "Explorer"
    case sourceControl = "Git"

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .explorer: "folder"
        case .sourceControl: "arrow.triangle.branch"
        }
    }
}

private struct WorkspaceSidebarTabButtonStyle: ButtonStyle {
    let isSelected: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .frame(height: AtelierMetrics.panelHeaderHeight - 8)
            .background(
                tabFill(isPressed: configuration.isPressed),
                in: RoundedRectangle(cornerRadius: AtelierTheme.rowRadius, style: .continuous)
            )
            .padding(.horizontal, AtelierMetrics.spaceXS)
            .padding(.vertical, 4)
            .frame(height: AtelierMetrics.panelHeaderHeight)
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .animation(
                reduceMotion ? nil : .easeOut(duration: AtelierMotionTokens.quick),
                value: isHovering
            )
            .atelierPointerCursor()
    }

    private func tabFill(isPressed: Bool) -> Color {
        if isPressed { return AtelierTheme.pressedFill }
        if isSelected { return .clear }
        if isHovering { return AtelierTheme.hoverFill }
        return .clear
    }
}

nonisolated enum WorkspaceLayoutPolicy {
    static let compactBreakpoint: CGFloat = 900
    static let wideBreakpoint: CGFloat = 1_280

    static func mode(containerWidth: CGFloat) -> WorkspaceLayoutMode {
        if containerWidth < compactBreakpoint { return .compact }
        if containerWidth < wideBreakpoint { return .standard }
        return .wide
    }

}

nonisolated enum ProjectCommandLayoutPolicy {
    static func workspaceHorizontalOffset(workspaceRailWidth: CGFloat) -> CGFloat {
        -workspaceRailWidth / 2
    }

    static func toolbarCorrection(windowWidth: CGFloat, itemFrame: CGRect) -> CGFloat {
        windowWidth / 2 - itemFrame.midX
    }
}

nonisolated struct WorkspacePanelPresentation: Equatable, Sendable {
    var showsSidebar: Bool
    var showsInspector: Bool
    var restoresSidebarAfterInspector: Bool

    var hasVisiblePanel: Bool { showsSidebar || showsInspector }

    static func initial(for layout: WorkspaceLayoutMode) -> WorkspacePanelPresentation {
        WorkspacePanelPresentation(
            showsSidebar: layout.docksSidebar,
            showsInspector: layout.showsInspectorByDefault,
            restoresSidebarAfterInspector: layout.docksSidebar
        )
    }

    func adapting(
        from oldLayout: WorkspaceLayoutMode,
        to newLayout: WorkspaceLayoutMode
    ) -> WorkspacePanelPresentation {
        if newLayout == .compact {
            return .initial(for: .compact)
        }
        if oldLayout == .compact {
            return .initial(for: newLayout)
        }
        if newLayout == .wide {
            return .initial(for: .wide)
        }
        if showsInspector {
            return WorkspacePanelPresentation(
                showsSidebar: false,
                showsInspector: true,
                restoresSidebarAfterInspector: showsSidebar
            )
        }
        return WorkspacePanelPresentation(
            showsSidebar: true,
            showsInspector: false,
            restoresSidebarAfterInspector: true
        )
    }

    func togglingSidebar(layout: WorkspaceLayoutMode) -> WorkspacePanelPresentation {
        guard layout.docksSidebar else { return self }
        if showsSidebar {
            return WorkspacePanelPresentation(
                showsSidebar: false,
                showsInspector: showsInspector,
                restoresSidebarAfterInspector: restoresSidebarAfterInspector
            )
        }
        return WorkspacePanelPresentation(
            showsSidebar: true,
            showsInspector: layout.keepsSidebarWithInspector ? showsInspector : false,
            restoresSidebarAfterInspector: true
        )
    }

    func togglingInspector(layout: WorkspaceLayoutMode) -> WorkspacePanelPresentation {
        guard layout.supportsInspector else { return self }
        if showsInspector {
            return WorkspacePanelPresentation(
                showsSidebar: layout.keepsSidebarWithInspector
                    ? showsSidebar
                    : restoresSidebarAfterInspector,
                showsInspector: false,
                restoresSidebarAfterInspector: restoresSidebarAfterInspector
            )
        }
        return WorkspacePanelPresentation(
            showsSidebar: layout.keepsSidebarWithInspector ? showsSidebar : false,
            showsInspector: true,
            restoresSidebarAfterInspector: showsSidebar
        )
    }

    func settingAllPanelsPresented(
        _ isPresented: Bool,
        layout: WorkspaceLayoutMode
    ) -> WorkspacePanelPresentation {
        isPresented ? .initial(for: layout) : .initial(for: .compact)
    }

    func togglingAllPanels(layout: WorkspaceLayoutMode) -> WorkspacePanelPresentation {
        settingAllPanelsPresented(!hasVisiblePanel, layout: layout)
    }
}

@MainActor
@Observable
final class WorkspaceChromeModel {
    var panels = WorkspacePanelPresentation.initial(for: .standard)
    var currentLayoutMode = WorkspaceLayoutMode.standard
    var selectedSidebarTab = WorkspaceSidebarTab.explorer
    var explorerRevealRequest: FileTreeRevealRequest?
    var agentResponseOverlayMode = AgentResponseOverlayMode.half
    var isProjectMenuPresented = false
    var sidebarAnimationRequestID = 0
    var inspectorAnimationRequestID = 0
    var projectCommandToolbarOffset: CGFloat = 0
    private var hasAppliedInitialLayout = false
    private var initialLayoutProfilePanels: LayoutProfilePanelState?
    private var projectMenuTransitionID = 0
    private var responderBeforeProjectMenu: NSResponder?
    private var responderBeforeInspector: NSResponder?
    private var responderBeforeAgentResponses: NSResponder?

    var layoutProfilePanelState: LayoutProfilePanelState {
        LayoutProfilePanelState(
            showsSidebar: panels.showsSidebar,
            showsInspector: panels.showsInspector,
            restoresSidebarAfterInspector: panels.restoresSidebarAfterInspector,
            selectedSidebarTab: selectedSidebarTab
        )
    }

    func applyInitialLayout(_ layout: WorkspaceLayoutMode) {
        guard !hasAppliedInitialLayout else { return }
        hasAppliedInitialLayout = true
        currentLayoutMode = layout
        if let initialLayoutProfilePanels {
            selectedSidebarTab = initialLayoutProfilePanels.selectedSidebarTab
            panels = initialLayoutProfilePanels.presentation(for: layout)
            self.initialLayoutProfilePanels = nil
        } else {
            panels = .initial(for: layout)
        }
    }

    func adaptPanels(
        from oldLayout: WorkspaceLayoutMode,
        to newLayout: WorkspaceLayoutMode,
        isFocusMode: Bool
    ) {
        currentLayoutMode = newLayout
        guard !isFocusMode else { return }
        panels = panels.adapting(from: oldLayout, to: newLayout)
    }

    func applyPanelPresentation(
        _ nextPanels: WorkspacePanelPresentation,
        requestsAnimation: Bool
    ) {
        if requestsAnimation && panels.showsSidebar != nextPanels.showsSidebar {
            sidebarAnimationRequestID += 1
        }
        if requestsAnimation && panels.showsInspector != nextPanels.showsInspector {
            inspectorAnimationRequestID += 1
        }
        panels = nextPanels
    }

    func applyLayoutProfilePanels(
        _ nextPanels: LayoutProfilePanelState,
        requestsAnimation: Bool
    ) {
        selectedSidebarTab = nextPanels.selectedSidebarTab
        guard hasAppliedInitialLayout else {
            initialLayoutProfilePanels = nextPanels
            return
        }
        applyPanelPresentation(
            nextPanels.presentation(for: currentLayoutMode),
            requestsAnimation: requestsAnimation
        )
    }

    func toggleSidebar() {
        sidebarAnimationRequestID += 1
        panels = panels.togglingSidebar(layout: currentLayoutMode)
    }

    func showSidebarTab(_ tab: WorkspaceSidebarTab) {
        selectedSidebarTab = tab
        guard currentLayoutMode.docksSidebar, !panels.showsSidebar else { return }
        toggleSidebar()
    }

    func requestExplorerReveal(_ url: URL) {
        explorerRevealRequest = FileTreeRevealRequest(url: url)
    }

    func toggleAgentResponses(
        session: WorkspaceSession,
        windowController: WindowController
    ) {
        if session.isAgentSidecarPresented {
            closeAgentResponses(session: session, windowController: windowController)
        } else {
            openAgentResponses(session: session, windowController: windowController)
        }
    }

    func openAgentResponses(
        session: WorkspaceSession,
        windowController: WindowController
    ) {
        guard !session.isAgentSidecarPresented else { return }
        responderBeforeAgentResponses = windowController.currentFirstResponder()
        agentResponseOverlayMode = .half
        session.openAgentSidecar()
    }

    func closeAgentResponses(
        session: WorkspaceSession,
        windowController: WindowController
    ) {
        guard session.isAgentSidecarPresented else { return }
        let responder = responderBeforeAgentResponses
        responderBeforeAgentResponses = nil
        session.closeAgentSidecar()
        Task { @MainActor in
            await Task.yield()
            windowController.restoreFirstResponder(responder)
        }
    }

    func toggleAgentResponseOverlayMode() {
        agentResponseOverlayMode = agentResponseOverlayMode == .full ? .half : .full
    }

    func updateFocusMode(_ isFocused: Bool) {
        applyPanelPresentation(
            panels.settingAllPanelsPresented(!isFocused, layout: currentLayoutMode),
            requestsAnimation: true
        )
    }

    func toggleInspector(windowController: WindowController) {
        guard currentLayoutMode.supportsInspector else { return }
        responderBeforeInspector = windowController.currentFirstResponder()
        inspectorAnimationRequestID += 1
        panels = panels.togglingInspector(layout: currentLayoutMode)
        Task { @MainActor in
            await Task.yield()
            windowController.restoreFirstResponder(responderBeforeInspector)
            responderBeforeInspector = nil
        }
    }

    func toggleProjectMenu(windowController: WindowController, reduceMotion: Bool) {
        if isProjectMenuPresented {
            dismissProjectMenu(windowController: windowController, reduceMotion: reduceMotion)
            return
        }

        projectMenuTransitionID += 1
        responderBeforeProjectMenu = windowController.currentFirstResponder()
        withAnimation(reduceMotion ? nil : AtelierMotionTokens.panel) {
            isProjectMenuPresented = true
        }
    }

    func dismissProjectMenu(
        restoresResponder: Bool = true,
        windowController: WindowController,
        reduceMotion: Bool
    ) {
        guard isProjectMenuPresented else { return }

        projectMenuTransitionID += 1
        let transitionID = projectMenuTransitionID
        let responder = responderBeforeProjectMenu
        responderBeforeProjectMenu = nil

        withAnimation(reduceMotion ? nil : AtelierMotionTokens.panel) {
            isProjectMenuPresented = false
        }

        guard restoresResponder, let responder else { return }
        Task { @MainActor in
            if reduceMotion {
                await Task.yield()
            } else {
                try? await Task.sleep(for: .seconds(AtelierMotionTokens.deliberate))
            }
            guard transitionID == projectMenuTransitionID,
                  !isProjectMenuPresented else { return }
            windowController.restoreFirstResponder(responder)
        }
    }
}

struct ContentView: View {
    @Environment(AppModel.self) private var app
    @Environment(AtelierZoomModel.self) private var zoom
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var commandPaletteModel = AtelierPaletteModel()
    @State private var presentedPaletteMode: AtelierPaletteMode?
    @State private var responderBeforePalette: NSResponder?
    @State private var responderBeforeWorkspaceSearch: NSResponder?

    var body: some View {
        ZStack(alignment: .top) {
            HStack(spacing: 0) {
                WorkspaceRailView()

                ZStack {
                    ForEach(app.liveSessions, id: \.state.id) { workspace in
                        let isActive = workspace.state.id == app.selectedWorkspaceID
                        WorkspaceView(
                            session: workspace,
                            isActive: isActive,
                            sidebarWidth: app.workspaceSidebarWidth,
                            inspectorWidth: app.workspaceInspectorWidth
                        )
                            .opacity(isActive ? 1 : 0)
                            .allowsHitTesting(isActive)
                            .accessibilityHidden(!isActive)
                            .zIndex(isActive ? 1 : 0)
                    }

                    if app.workspace == nil {
                        if let item = app.selectedWorkspaceItem,
                           case .unavailable(let message) = item.status {
                            WorkspaceUnavailableView(item: item, message: message)
                                .zIndex(2)
                        } else if let item = app.selectedWorkspaceItem,
                                  case .error(let message) = item.status {
                            WorkspaceUnavailableView(item: item, message: message)
                                .zIndex(2)
                        } else {
                            EmptyStateView()
                                .zIndex(2)
                        }
                    }
                }
            }

            if let presentedPaletteMode {
                paletteOverlay(mode: presentedPaletteMode)
                    .zIndex(10)
            }

            if let workspace = app.workspace {
                workspaceSearchOverlay(model: workspace.workspaceSearchModel)
                    .opacity(workspace.workspaceSearchModel.isPresented ? 1 : 0)
                    .allowsHitTesting(workspace.workspaceSearchModel.isPresented)
                    .accessibilityHidden(!workspace.workspaceSearchModel.isPresented)
                    .zIndex(workspace.workspaceSearchModel.isPresented ? 11 : -1)
            }
        }
        .background(AtelierTheme.canvas)
        .tint(AtelierTheme.accent)
        .toolbar {
            if let workspace = app.workspace {
                workspaceToolbar(for: workspace)
            }
        }
        .navigationTitle(app.workspace.map(Self.folderName) ?? "")
        .focusedSceneValue(\.showQuickOpen, quickOpenAction)
        .focusedSceneValue(\.showWorkspaceSearch, workspaceSearchAction)
        .focusedSceneValue(\.showCommandPalette) {
            presentPalette(.commands)
        }
        .onChange(of: app.selectedWorkspaceID) { _, _ in
            if presentedPaletteMode != nil {
                dismissPalette(restoresResponder: false)
            }
            for session in app.liveSessions where session.workspaceSearchModel.isPresented {
                session.workspaceSearchModel.dismiss()
            }
            responderBeforeWorkspaceSearch = nil
        }
    }

    static func folderName(for session: WorkspaceSession) -> String {
        (session.state.path as NSString).lastPathComponent
    }

    @ToolbarContentBuilder
    private func workspaceToolbar(for session: WorkspaceSession) -> some ToolbarContent {
        let chrome = session.chrome
        let folderName = Self.folderName(for: session)

        ToolbarItem(placement: .navigation) {
            Button {
                chrome.dismissProjectMenu(
                    restoresResponder: false,
                    windowController: app.windowController,
                    reduceMotion: reduceMotion
                )
                AtelierActionRegistry.perform(.toggleLeftPanel, model: app)
            } label: {
                Image(systemName: "sidebar.leading")
            }
            .accessibilityLabel(chrome.panels.showsSidebar ? "Hide Sidebar" : "Show Sidebar")
            .help(chrome.panels.showsSidebar ? "Hide Sidebar" : "Show Sidebar")
            .disabled(zoom.isFocusMode || !chrome.currentLayoutMode.docksSidebar)
            .atelierPointerCursor()
        }

        ToolbarItem(placement: .principal) {
            Button {
                chrome.toggleProjectMenu(
                    windowController: app.windowController,
                    reduceMotion: reduceMotion
                )
            } label: {
                ProjectMenuLabel(projectName: folderName)
                    .frame(width: AtelierMetrics.projectMenuWidth)
                    .atelierGlassControl(isSelected: chrome.isProjectMenuPresented)
                    .background {
                        ProjectCommandToolbarCenterBridge { correction in
                            chrome.projectCommandToolbarOffset += correction
                        }
                    }
            }
            .buttonStyle(.plain)
            .contentShape(
                RoundedRectangle(cornerRadius: AtelierTheme.controlRadius, style: .continuous)
            )
            .help("\(folderName)\n\(session.state.path)\nProject commands")
            .accessibilityLabel("Project commands for \(folderName)")
            .accessibilityValue(chrome.isProjectMenuPresented ? "Open" : "Closed")
            .atelierPointerCursor()
            .offset(x: chrome.projectCommandToolbarOffset)
        }
        .sharedBackgroundVisibility(.hidden)

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                chrome.dismissProjectMenu(
                    restoresResponder: false,
                    windowController: app.windowController,
                    reduceMotion: reduceMotion
                )
                session.openGemma()
            } label: {
                Image(systemName: "sparkles")
            }
            .accessibilityLabel("Open Gemma workspace assistant")
            .help("Open Gemma workspace assistant")
            .atelierPointerCursor()

            Button {
                chrome.dismissProjectMenu(
                    restoresResponder: false,
                    windowController: app.windowController,
                    reduceMotion: reduceMotion
                )
                withAnimation(reduceMotion ? nil : AtelierMotionTokens.panel) {
                    AtelierActionRegistry.perform(.toggleWatchtower, model: app)
                }
            } label: {
                Image(systemName: "binoculars")
            }
            .accessibilityLabel(
                session.isWatchtowerPresented ? "Hide Watchtower plan" : "Show Watchtower plan"
            )
            .help(
                session.isWatchtowerPresented ? "Hide Watchtower Plan" : "Show Watchtower Plan"
            )
            .atelierPointerCursor()

            Button {
                chrome.dismissProjectMenu(
                    restoresResponder: false,
                    windowController: app.windowController,
                    reduceMotion: reduceMotion
                )
                AtelierActionRegistry.perform(.toggleWorkspacePanels, model: app)
            } label: {
                Image(
                    systemName: workspacePanelsArePresented(chrome: chrome)
                        ? "rectangle.center.inset.filled"
                        : "rectangle.split.3x1"
                )
            }
            .accessibilityLabel(
                workspacePanelsArePresented(chrome: chrome)
                    ? "Hide workspace panels"
                    : "Show workspace panels"
            )
            .help(
                workspacePanelsArePresented(chrome: chrome)
                    ? "Hide Workspace Panels"
                    : "Show Workspace Panels"
            )
            .atelierPointerCursor()

            Button {
                chrome.dismissProjectMenu(
                    restoresResponder: false,
                    windowController: app.windowController,
                    reduceMotion: reduceMotion
                )
                AtelierActionRegistry.perform(.toggleRightPanel, model: app)
            } label: {
                Image(systemName: "sidebar.trailing")
            }
            .accessibilityLabel(chrome.panels.showsInspector ? "Hide inspector" : "Show inspector")
            .help(chrome.panels.showsInspector ? "Hide Inspector" : "Show Inspector")
            .disabled(zoom.isFocusMode || !chrome.currentLayoutMode.supportsInspector)
            .atelierPointerCursor()
        }
    }

    private func workspacePanelsArePresented(chrome: WorkspaceChromeModel) -> Bool {
        !zoom.isFocusMode && chrome.panels.hasVisiblePanel
    }

    private var quickOpenAction: (() -> Void)? {
        guard app.workspace != nil else { return nil }
        return { presentPalette(.files) }
    }

    private var workspaceSearchAction: (() -> Void)? {
        guard app.workspace != nil else { return nil }
        return { presentWorkspaceSearch() }
    }

    private var activePaletteModel: AtelierPaletteModel {
        if presentedPaletteMode == .files, let workspace = app.workspace {
            return workspace.paletteModel
        }
        return commandPaletteModel
    }

    private func paletteOverlay(mode: AtelierPaletteMode) -> some View {
        ZStack(alignment: .top) {
            AtelierTheme.scrim
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    dismissPalette(restoresResponder: true)
                }
                .atelierPointerCursor()

            AtelierPaletteView(
                model: activePaletteModel,
                actionContext: AtelierActionRegistry.context(for: app),
                onActivate: activate,
                onDismiss: { dismissPalette(restoresResponder: true) }
            )
            .padding(.horizontal, AtelierMetrics.spaceL)
            .padding(.top, 54)
        }
        .transition(.opacity)
        .accessibilityAddTraits(.isModal)
    }

    private func workspaceSearchOverlay(model: WorkspaceSearchModel) -> some View {
        ZStack(alignment: .top) {
            AtelierTheme.scrim
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    dismissWorkspaceSearch(restoresResponder: true)
                }
                .atelierPointerCursor()

            WorkspaceSearchView(
                model: model,
                isPresented: model.isPresented,
                onActivate: activateWorkspaceSearch,
                onActivateGemmaSource: activateWorkspaceGemmaSource,
                onDismiss: { dismissWorkspaceSearch(restoresResponder: true) }
            )
            .padding(
                .leading,
                AtelierMetrics.workspaceRailWidth + AtelierMetrics.spaceL
            )
            .padding(.trailing, AtelierMetrics.spaceL)
            .padding(.vertical, AtelierMetrics.spaceL)
        }
        .accessibilityAddTraits(.isModal)
    }

    private func presentPalette(_ mode: AtelierPaletteMode) {
        let priorResponder = responderBeforeWorkspaceSearch
        if app.workspace?.workspaceSearchModel.isPresented == true {
            dismissWorkspaceSearch(restoresResponder: false)
        }
        responderBeforePalette = priorResponder
            ?? app.windowController.currentFirstResponder()
        switch mode {
        case .files:
            guard let workspace = app.workspace else { return }
            workspace.paletteModel.showFiles(revision: workspace.fileTreeRevision)
        case .commands:
            commandPaletteModel.showCommands(context: AtelierActionRegistry.context(for: app))
        }
        presentedPaletteMode = mode
    }

    private func activate(_ selection: AtelierPaletteSelection) {
        switch selection {
        case .file(let url):
            dismissPalette(restoresResponder: false)
            app.workspace?.terminalTabs.openFile(url)
        case .action(let action):
            let context = AtelierActionRegistry.context(for: app)
            guard AtelierActionRegistry.isEnabled(action, context: context) else { return }
            if action == .searchWorkspace {
                let responder = responderBeforePalette
                dismissPalette(restoresResponder: false)
                presentWorkspaceSearch(responder: responder)
                return
            }
            dismissPalette(restoresResponder: false)
            AtelierActionRegistry.perform(action, model: app)
        }
    }

    private func presentWorkspaceSearch(responder: NSResponder? = nil) {
        guard app.workspace != nil else { return }
        let priorResponder = responder ?? responderBeforePalette
        if presentedPaletteMode != nil {
            dismissPalette(restoresResponder: false)
        }
        responderBeforeWorkspaceSearch = priorResponder
            ?? app.windowController.currentFirstResponder()
        AtelierActionRegistry.perform(.searchWorkspace, model: app)
    }

    private func activateWorkspaceSearch(_ match: WorkspaceSearchMatch) {
        dismissWorkspaceSearch(restoresResponder: false)
        app.workspace?.terminalTabs.openFile(
            match.candidate.url,
            line: match.lineNumber
        )
    }

    private func activateWorkspaceGemmaSource(_ source: WorkspaceGemmaSearchSource) {
        guard let workspace = app.workspace else { return }
        let proposed = source.path.hasPrefix("/")
            ? URL(fileURLWithPath: source.path)
            : workspace.rootURL.appending(path: source.path)
        let resolved = proposed.standardizedFileURL.resolvingSymlinksInPath()
        guard resolved.pathComponents.starts(with: workspace.rootURL.pathComponents) else {
            return
        }
        dismissWorkspaceSearch(restoresResponder: false)
        workspace.terminalTabs.openFile(resolved, line: source.lineNumber)
    }

    private func dismissWorkspaceSearch(restoresResponder: Bool) {
        app.workspace?.workspaceSearchModel.dismiss()
        if restoresResponder {
            app.windowController.restoreFirstResponder(responderBeforeWorkspaceSearch)
        }
        responderBeforeWorkspaceSearch = nil
    }

    private func dismissPalette(restoresResponder: Bool) {
        activePaletteModel.dismiss()
        presentedPaletteMode = nil
        if restoresResponder {
            app.windowController.restoreFirstResponder(responderBeforePalette)
        }
        responderBeforePalette = nil
    }
}

struct EmptyStateView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack {
            AtelierWelcomeBackdrop()

            VStack(alignment: .leading, spacing: AtelierMetrics.spaceL) {
                Text("ATELIER")
                    .atelierFont(
                        size: AtelierTypography.micro,
                        weight: .bold,
                        design: .monospaced
                    )
                    .tracking(2.4)
                    .foregroundStyle(AtelierTheme.accent)

                Text("A quieter place to build.")
                    .atelierFont(
                        size: 34,
                        weight: .semibold,
                        design: .serif
                    )
                    .tracking(-0.8)

                Text("Open a local folder to edit files, run commands, and review Git changes in one native workspace.")
                    .atelierFont(size: AtelierTypography.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 430, alignment: .leading)

                HStack(spacing: AtelierMetrics.spaceM) {
                    Button("Open Folder") {
                        AtelierActionRegistry.perform(.openFolder, model: app)
                    }
                    .buttonStyle(AtelierLuminarePrimaryButtonStyle())
                    .keyboardShortcut("o", modifiers: .command)

                    Text("Command-O")
                        .atelierFont(size: AtelierTypography.caption, design: .monospaced)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(AtelierMetrics.space2XL * 2)
            .frame(maxWidth: 680, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AtelierTheme.canvas)
    }
}

private struct AtelierWelcomeBackdrop: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                Rectangle()
                    .fill(AtelierTheme.canvas)

                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                AtelierTheme.accent.opacity(0.22),
                                AtelierTheme.accent.opacity(0.04),
                                .clear
                            ],
                            center: .center,
                            startRadius: 8,
                            endRadius: min(geometry.size.width, geometry.size.height) * 0.48
                        )
                    )
                    .frame(
                        width: geometry.size.width * 0.72,
                        height: geometry.size.height * 0.92
                    )
                    .offset(x: geometry.size.width * 0.14, y: -geometry.size.height * 0.18)

                Circle()
                    .stroke(AtelierTheme.accent.opacity(0.12), lineWidth: 1)
                    .frame(width: min(geometry.size.width, geometry.size.height) * 0.72)
                    .offset(x: 100, y: -90)

                Rectangle()
                    .fill(AtelierTheme.accent.opacity(0.14))
                    .frame(width: 1, height: geometry.size.height * 0.56)
                    .padding(.trailing, geometry.size.width * 0.22)
                    .padding(.top, geometry.size.height * 0.18)

            }
        }
        .accessibilityHidden(true)
    }
}

struct WorkspaceView: View {
    let session: WorkspaceSession
    let isActive: Bool
    let sidebarWidth: CGFloat
    let inspectorWidth: CGFloat
    @Environment(AppModel.self) private var app
    @Environment(AtelierZoomModel.self) private var zoom
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var fileTreeCreationRequest: FileTreeCreationRequest?
    @State private var fileTreeTargetDirectory: URL?
    @State private var sidebarTabFrames: [WorkspaceSidebarTab: CGRect] = [:]

    var body: some View {
        GeometryReader { outerGeometry in
            let workspaceLayout = WorkspaceLayoutPolicy.mode(
                containerWidth: outerGeometry.size.width
            )

            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    workspaceSurface
                    statusBar
                }

                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismissProjectMenu()
                    }
                    .atelierPointerCursor()
                    .accessibilityHidden(true)
                    .allowsHitTesting(chrome.isProjectMenuPresented)

                ProjectCommandMenuView(
                    session: session,
                    workspaceURL: workspaceURL,
                    isPresented: chrome.isProjectMenuPresented,
                    onDismiss: { dismissProjectMenu() }
                )
                .modifier(
                    ProjectMenuRevealModifier(
                        progress: chrome.isProjectMenuPresented ? 1 : 0
                    )
                )
                .offset(
                    x: ProjectCommandLayoutPolicy.workspaceHorizontalOffset(
                        workspaceRailWidth: AtelierMetrics.workspaceRailWidth
                    )
                )
                .allowsHitTesting(chrome.isProjectMenuPresented)
                .accessibilityHidden(!chrome.isProjectMenuPresented)
                .zIndex(1)

                if session.isWatchtowerPresented {
                    watchtowerOverlay
                        .zIndex(2)
                }
            }
            .background(AtelierTheme.editor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                chrome.applyInitialLayout(workspaceLayout)
            }
            .onChange(of: workspaceLayout) { oldLayout, newLayout in
                // Defer off the current layout pass. During a window zoom the
                // GeometryReader width crosses a breakpoint mid-resize; mutating
                // panel state synchronously re-enters AppKit's layout cycle and
                // macOS traps in -[NSWindow _postWindowNeedsUpdateConstraints].
                Task { @MainActor in
                    chrome.adaptPanels(
                        from: oldLayout,
                        to: newLayout,
                        isFocusMode: zoom.isFocusMode
                    )
                }
            }
            .onChange(of: zoom.isFocusMode) { _, isFocused in
                chrome.updateFocusMode(isFocused)
            }
            .onChange(of: isActive) { _, isActive in
                if !isActive {
                    dismissProjectMenu(restoresResponder: false)
                }
            }
            .onExitCommand {
                dismissProjectMenu()
            }
        }
    }

    private var chrome: WorkspaceChromeModel { session.chrome }

    private func dismissProjectMenu(restoresResponder: Bool = true) {
        chrome.dismissProjectMenu(
            restoresResponder: restoresResponder,
            windowController: app.windowController,
            reduceMotion: reduceMotion
        )
    }

    private var state: WorkspaceState { session.state }
    private var terminalTabs: TerminalTabsModel { session.terminalTabs }
    private var gitModel: GitWorkspaceModel { session.gitModel }

    private var folderName: String {
        (state.path as NSString).lastPathComponent
    }

    private var workspaceURL: URL {
        URL(fileURLWithPath: state.path, isDirectory: true)
    }

    private var workspaceSurface: some View {
        WorkspaceNativeSplitView(
            sidebar: workspaceSidebar
                .frame(idealWidth: AtelierMetrics.workspaceSidebarIdealWidth)
                .environment(app)
                .environment(zoom),
            detail: workspaceDetail
                .environment(app)
                .environment(zoom),
            inspector: GemmaSidecarView(model: session.gemmaSidecar)
                .frame(idealWidth: AtelierMetrics.inspectorIdealWidth)
                .environment(app)
                .environment(zoom),
            sidebarWidth: sidebarWidth,
            inspectorWidth: inspectorWidth,
            onSidebarWidthChange: app.updateWorkspaceSidebarWidth,
            onInspectorWidthChange: app.updateWorkspaceInspectorWidth,
            showsSidebar: chrome.panels.showsSidebar && !zoom.isFocusMode,
            showsInspector: chrome.panels.showsInspector && !zoom.isFocusMode,
            sidebarAnimationRequestID: chrome.sidebarAnimationRequestID,
            inspectorAnimationRequestID: chrome.inspectorAnimationRequestID,
            reduceMotion: reduceMotion
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var workspaceDetail: some View {
        TerminalTabs(
            model: terminalTabs,
            agentResponses: session.agentResponses,
            isWorkspaceActive: isActive,
            isAgentSidecarPresented: session.isAgentSidecarPresented,
            agentResponseOverlayMode: chrome.agentResponseOverlayMode,
            onOpenAgentSidecar: openAgentSidecar,
            onCloseAgentSidecar: closeAgentSidecar,
            onToggleAgentResponseOverlayMode: toggleAgentResponseOverlayMode
        )
        .frame(
            minWidth: AtelierMetrics.centerMinWidth,
            idealWidth: AtelierMetrics.centerIdealWidth
        )
        .layoutPriority(2)
        .overlay(alignment: .leading) {
            if chrome.panels.showsSidebar && !zoom.isFocusMode {
                LinearGradient(
                    colors: [AtelierTheme.panelEdgeShadow, .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                    .frame(width: AtelierMetrics.spaceM / 2)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .trailing) {
            if chrome.panels.showsInspector && !zoom.isFocusMode {
                LinearGradient(
                    colors: [.clear, AtelierTheme.panelEdgeShadow],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                    .frame(width: AtelierMetrics.spaceM / 2)
                    .allowsHitTesting(false)
            }
        }
    }

    private func openAgentSidecar() {
        chrome.openAgentResponses(
            session: session,
            windowController: app.windowController
        )
    }

    private func closeAgentSidecar() {
        chrome.closeAgentResponses(
            session: session,
            windowController: app.windowController
        )
    }

    private func toggleAgentResponseOverlayMode() {
        withAnimation(reduceMotion ? nil : AtelierMotionTokens.panel) {
            chrome.toggleAgentResponseOverlayMode()
        }
    }

    // Floating trailing panel. It lives in the ZStack outside the native split
    // view, so it overlays the editor without changing the split's proposed size
    // at any window width. Toggled by user action only, never layout-derived.
    private var watchtowerOverlay: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            WatchtowerPanelView(
                model: session.watchtower,
                onOpenFile: { terminalTabs.previewFile($0) },
                onClose: { closeWatchtower() }
            )
                .frame(width: AtelierMetrics.watchtowerPanelWidth, alignment: .leading)
                .frame(maxHeight: .infinity)
                .background(AtelierTheme.panel)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(AtelierTheme.border)
                        .frame(width: AtelierTheme.strokeHairline)
                }
                .shadow(color: AtelierTheme.shadowFloating, radius: 18, x: -6, y: 0)
                .onExitCommand { closeWatchtower() }
        }
        .transition(.move(edge: .trailing))
    }

    private func closeWatchtower() {
        withAnimation(reduceMotion ? nil : AtelierMotionTokens.panel) {
            session.closeWatchtower()
        }
    }

    private var workspaceSidebar: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                if let frame = sidebarTabFrames[chrome.selectedSidebarTab]?.insetBy(
                    dx: AtelierMetrics.spaceXS,
                    dy: 4
                ) {
                    AtelierMovingGlassIndicator(
                        frame: frame,
                        tint: AtelierTheme.chromeSelection.opacity(0.5),
                        fallbackFill: AtelierTheme.chromeSelection
                    )
                }

                HStack(spacing: 0) {
                    ForEach(WorkspaceSidebarTab.allCases) { tab in
                        WorkspaceSidebarTabButton(
                            tab: tab,
                            isSelected: chrome.selectedSidebarTab == tab,
                            gitModel: gitModel
                        ) {
                            chrome.selectedSidebarTab = tab
                        }
                        .background {
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: WorkspaceSidebarTabFramePreferenceKey.self,
                                    value: [
                                        tab: proxy.frame(
                                            in: .named("workspaceSidebarTabs")
                                        )
                                    ]
                                )
                            }
                        }
                    }
                }
            }
            .coordinateSpace(.named("workspaceSidebarTabs"))
            .onPreferenceChange(WorkspaceSidebarTabFramePreferenceKey.self) { frames in
                guard sidebarTabFrames != frames else { return }
                Task { @MainActor in
                    guard sidebarTabFrames != frames else { return }
                    sidebarTabFrames = frames
                }
            }
            .clipped()
            .frame(height: AtelierMetrics.panelHeaderHeight)
            .background {
                AtelierChromeBackground()
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(AtelierTheme.border)
                    .frame(height: AtelierTheme.strokeHairline)
            }
            .environment(\.atelierZoomScale, zoom.sidebarScale)

            sidebarBodyToolbar

            ZStack {
                explorerContent
                    .opacity(chrome.selectedSidebarTab == .explorer ? 1 : 0)
                    .allowsHitTesting(chrome.selectedSidebarTab == .explorer)
                    .disabled(chrome.selectedSidebarTab != .explorer)
                    .accessibilityHidden(chrome.selectedSidebarTab != .explorer)

                ChangesView(
                    model: gitModel,
                    selectedDiff: terminalTabs.selectedGitDiffSelection,
                    onOpenDiff: terminalTabs.openGitDiff,
                    isActive: chrome.selectedSidebarTab == .sourceControl,
                    showsPanelHeader: false
                )
                .opacity(chrome.selectedSidebarTab == .sourceControl ? 1 : 0)
                .allowsHitTesting(chrome.selectedSidebarTab == .sourceControl)
                .disabled(chrome.selectedSidebarTab != .sourceControl)
                .accessibilityHidden(chrome.selectedSidebarTab != .sourceControl)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .background(AtelierTheme.sidebar)
    }

    @ViewBuilder
    private var sidebarBodyToolbar: some View {
        HStack(spacing: 2) {
            Spacer(minLength: 0)

            switch chrome.selectedSidebarTab {
            case .explorer:
                Group {
                    Button {
                        AtelierActionRegistry.perform(.revealActiveFileInExplorer, model: app)
                    } label: {
                        Image(systemName: "scope")
                    }
                    .accessibilityLabel("Reveal active file in Explorer")
                    .help("Reveal active file in Explorer (Command-B)")
                    .disabled(
                        !AtelierActionRegistry.isEnabled(
                            .revealActiveFileInExplorer,
                            context: AtelierActionRegistry.context(for: app)
                        )
                    )

                    Button {
                        fileTreeCreationRequest = FileTreeCreationRequest(
                            kind: .file,
                            parentURL: fileTreeTargetDirectory ?? workspaceURL
                        )
                    } label: {
                        Image(systemName: "doc.badge.plus")
                    }
                    .accessibilityLabel("New file")
                    .help("New file")

                    Button {
                        fileTreeCreationRequest = FileTreeCreationRequest(
                            kind: .folder,
                            parentURL: fileTreeTargetDirectory ?? workspaceURL
                        )
                    } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                    .accessibilityLabel("New folder")
                    .help("New folder")
                }
                .buttonStyle(AtelierRowIconButtonStyle())
            case .sourceControl:
                GitRefreshButton(gitModel: gitModel)
            }
        }
        .padding(.horizontal, AtelierMetrics.spaceS)
        .frame(height: AtelierMetrics.controlHeight)
        .background(AtelierTheme.sidebar)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AtelierTheme.border)
                .frame(height: AtelierTheme.strokeHairline)
        }
    }

    private var explorerContent: some View {
        VStack(spacing: 0) {
            if let request = fileTreeCreationRequest {
                ExplorerInlineCreationRow(
                    request: request,
                    workspaceURL: workspaceURL,
                    onCreate: { name in
                        switch request.kind {
                        case .file:
                            try await session.createFile(named: name, in: request.parentURL)
                        case .folder:
                            try await session.createFolder(named: name, in: request.parentURL)
                        }
                    },
                    onCancel: { fileTreeCreationRequest = nil },
                    onCreated: { fileTreeCreationRequest = nil }
                )
                .id(request.id)
                .environment(\.atelierZoomScale, zoom.sidebarScale)
            }

            ExplorerFileTree(
                gitModel: gitModel,
                rootURL: workspaceURL,
                revision: session.fileTreeRevision,
                revealRequest: chrome.explorerRevealRequest,
                onTargetDirectoryChange: { fileTreeTargetDirectory = $0 },
                onCreateItem: { kind, parentURL in
                    fileTreeCreationRequest = FileTreeCreationRequest(
                        kind: kind,
                        parentURL: parentURL
                    )
                },
                onRenameItem: { url, name in
                    Task {
                        do {
                            try await session.renameItem(at: url, to: name)
                        } catch {
                            app.presentedError = .workspace(error)
                        }
                    }
                },
                onMoveItemToTrash: { url in
                    Task {
                        do {
                            try await session.moveItemToTrash(at: url)
                        } catch {
                            app.presentedError = .workspace(error)
                        }
                    }
                },
                onAddItemToGitIgnore: { url in
                    Task {
                        do {
                            try await session.addItemToGitIgnore(url)
                        } catch {
                            app.presentedError = .workspace(error)
                        }
                    }
                },
                onPasteRelativePath: terminalTabs.pasteIntoSelectedTerminal,
                onPreview: terminalTabs.previewFile,
                onOpen: terminalTabs.openFile
            )
            .environment(\.atelierZoomScale, zoom.sidebarScale)
        }
        .background(AtelierTheme.sidebar)
    }

    private var statusBar: some View {
        HStack(spacing: AtelierMetrics.spaceM) {
            GitBranchLabel(gitModel: gitModel)
            Spacer()
            if zoom.isFocusMode {
                Text("Focus")
            }
            FileTokenCountLabel(editor: terminalTabs.selectedEditor)
            LayoutProfileStatusMenu()
        }
        .atelierFont(size: AtelierTypography.caption, weight: .medium)
        .foregroundStyle(.secondary)
        .padding(.horizontal, AtelierMetrics.spaceM)
        .frame(height: AtelierMetrics.statusBarHeight)
        .background {
            AtelierChromeBackground()
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AtelierTheme.border)
                .frame(height: AtelierTheme.strokeHairline)
        }
    }
}

private struct LayoutProfileStatusMenu: View {
    @Environment(AppModel.self) private var app
    @Environment(AtelierZoomModel.self) private var zoom

    private var profile: LayoutProfile {
        app.selectedLayoutProfile
    }

    private var isModified: Bool {
        app.isSelectedLayoutProfileModified
    }

    private var zoomPercent: Int {
        Int((zoom.scale * 100).rounded())
    }

    var body: some View {
        Menu {
            ForEach(app.layoutProfiles.profiles) { candidate in
                Button {
                    app.applyLayoutProfile(candidate.id)
                } label: {
                    Label(
                        candidate.title,
                        systemImage: candidate.id == profile.id
                            ? "checkmark"
                            : "rectangle"
                    )
                }
                .disabled(app.layoutProfiles.isApplying)
            }

            Divider()

            Button("Save Current to \(profile.title)") {
                app.saveCurrentLayoutProfile()
            }
            .disabled(app.layoutProfiles.isApplying)
        } label: {
            Text("\(profile.title)\(isModified ? " *" : "") \(zoomPercent)%")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(isModified ? "Layout profile has unsaved changes" : "Layout profile")
        .accessibilityLabel("Layout profile")
        .accessibilityValue(
            "\(profile.title), \(zoomPercent) percent\(isModified ? ", modified" : "")"
        )
        .atelierPointerCursor()
    }
}

private struct FileTokenCountLabel: View {
    let editor: EditorSession?

    var body: some View {
        if let editor, case .text = editor.content {
            let tokenCount = LLMTokenEstimator.estimate(
                byteCount: editor.diagnosticLoadedBytes
            )
            Text("~\(tokenCount.formatted()) tokens")
                .accessibilityLabel("Estimated LLM tokens")
                .accessibilityValue(tokenCount.formatted())
                .help("Estimated LLM tokens. Exact count depends on the model.")
        }
    }
}

// Git-dependent leaves live in their own views so a git snapshot change
// invalidates only these leaves instead of the whole WorkspaceView tree.
private struct WorkspaceSidebarTabButton: View {
    let tab: WorkspaceSidebarTab
    let isSelected: Bool
    let gitModel: GitWorkspaceModel
    let action: () -> Void

    var body: some View {
        let changeCount = tab == .sourceControl
            ? gitModel.snapshot.status.changes.count
            : 0

        Button(action: action) {
            Label(tab.rawValue, systemImage: tab.systemImage)
                .font(
                    .system(
                        size: AtelierTypography.uiSize,
                        weight: isSelected ? .semibold : .regular
                    )
                )
                .foregroundStyle(
                    isSelected
                        ? AtelierTheme.chromeSelectionInk
                        : Color.secondary
                )
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .trailing) {
                    if changeCount > 0 {
                        AtelierCountBadge(
                            value: changeCount,
                            color: AtelierTheme.gitOrange
                        )
                        .accessibilityHidden(true)
                        .padding(.trailing, AtelierMetrics.spaceM)
                    }
                }
        }
        .buttonStyle(
            WorkspaceSidebarTabButtonStyle(
                isSelected: isSelected
            )
        )
        .accessibilityLabel(
            changeCount > 0
                ? "\(tab.rawValue), \(changeCount) changes"
                : tab.rawValue
        )
        .accessibilityValue(
            isSelected ? "Selected" : "Not selected"
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(tab.rawValue)
        .frame(maxWidth: .infinity)
    }
}

private struct WorkspaceSidebarTabFramePreferenceKey: PreferenceKey {
    static var defaultValue: [WorkspaceSidebarTab: CGRect] = [:]

    static func reduce(
        value: inout [WorkspaceSidebarTab: CGRect],
        nextValue: () -> [WorkspaceSidebarTab: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct GitRefreshButton: View {
    let gitModel: GitWorkspaceModel

    var body: some View {
        Button {
            gitModel.refresh()
        } label: {
            if gitModel.isLoading {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: "arrow.clockwise")
            }
        }
        .buttonStyle(AtelierRowIconButtonStyle())
        .accessibilityLabel("Refresh Git status")
        .help("Refresh Git status")
    }
}

private struct GitBranchLabel: View {
    let gitModel: GitWorkspaceModel

    var body: some View {
        Label(
            gitModel.snapshot.branch.isEmpty ? "detached" : gitModel.snapshot.branch,
            systemImage: "arrow.triangle.branch"
        )
    }
}

private struct ExplorerFileTree: View {
    let gitModel: GitWorkspaceModel
    let rootURL: URL
    let revision: Int
    let revealRequest: FileTreeRevealRequest?
    let onTargetDirectoryChange: (URL) -> Void
    let onCreateItem: (FileTreeCreationKind, URL) -> Void
    let onRenameItem: (URL, String) -> Void
    let onMoveItemToTrash: (URL) -> Void
    let onAddItemToGitIgnore: (URL) -> Void
    let onPasteRelativePath: (String) -> Bool
    let onPreview: (URL) -> Void
    let onOpen: (URL) -> Void

    var body: some View {
        FileTreeView(
            rootURL: rootURL,
            revision: revision,
            revealRequest: revealRequest,
            ignoredPaths: gitModel.snapshot.status.ignoredPaths,
            onTargetDirectoryChange: onTargetDirectoryChange,
            onCreateItem: onCreateItem,
            onRenameItem: onRenameItem,
            onMoveItemToTrash: onMoveItemToTrash,
            onAddItemToGitIgnore: onAddItemToGitIgnore,
            onPasteRelativePath: onPasteRelativePath,
            onPreview: onPreview,
            onOpen: onOpen
        )
    }
}

private struct ProjectMenuLabel: View {
    let projectName: String

    var body: some View {
        Text(projectName)
            .atelierFont(size: AtelierTypography.body, weight: .semibold)
            .foregroundStyle(.primary)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, AtelierMetrics.spaceM)
            .frame(minHeight: AtelierMetrics.controlHeight)
            .contentShape(
                RoundedRectangle(cornerRadius: AtelierTheme.controlRadius, style: .continuous)
            )
    }
}

private struct ProjectCommandMenuView: View {
    private enum Command: CaseIterable, Hashable {
        case openFolder
        case showInFinder
        case copyProjectPath
        case newTerminal
        case openGemma
        case closeWorkspace
        case zoomIn
        case zoomOut
        case actualSize
    }

    let session: WorkspaceSession
    let workspaceURL: URL
    let isPresented: Bool
    let onDismiss: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(AtelierZoomModel.self) private var zoom
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isClosing = false
    @FocusState private var focusedCommand: Command?

    var body: some View {
        VStack(spacing: 0) {
            commandButton(.openFolder, "Open Folder...", systemImage: "folder") {
                AtelierActionRegistry.perform(.openFolder, model: app)
            }
            commandButton(
                .showInFinder,
                "Show in Finder",
                systemImage: "folder.badge.magnifyingglass"
            ) {
                NSWorkspace.shared.activateFileViewerSelecting([workspaceURL])
            }
            commandButton(
                .copyProjectPath,
                "Copy Project Path",
                systemImage: "doc.on.doc"
            ) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(session.state.path, forType: .string)
            }

            commandDivider

            commandButton(.newTerminal, "New Terminal", systemImage: "terminal") {
                AtelierActionRegistry.perform(.newTerminal, model: app)
            }
            commandButton(.openGemma, "Open Gemma", systemImage: "sparkles") {
                session.openGemma()
            }
            commandButton(
                .closeWorkspace,
                "Close Workspace",
                systemImage: "xmark.rectangle",
                role: .destructive
            ) {
                app.closeWorkspace(id: session.state.id)
            }

            commandDivider

            commandButton(
                .zoomIn,
                "Zoom In",
                systemImage: "plus.magnifyingglass",
                isEnabled: zoom.canZoomIn
            ) {
                app.windowController.maximizeWorkspaceWindow()
                zoom.zoomIn()
            }
            commandButton(
                .zoomOut,
                "Zoom Out",
                systemImage: "minus.magnifyingglass",
                isEnabled: zoom.canZoomOut
            ) {
                zoom.zoomOut()
            }
            commandButton(.actualSize, "Actual Size", systemImage: "1.magnifyingglass") {
                zoom.reset()
            }
        }
        .padding(AtelierMetrics.spaceS)
        .frame(width: AtelierMetrics.projectMenuWidth)
        .background {
            AtelierChromeBackground()
        }
        .clipShape(menuShape)
        .overlay {
            menuShape
                .stroke(AtelierTheme.border, lineWidth: AtelierTheme.strokeControl)
        }
        .shadow(color: AtelierTheme.shadowFloating, radius: 20, y: 10)
        .allowsHitTesting(!isClosing)
        .task(id: isPresented) {
            guard isPresented else {
                focusedCommand = nil
                isClosing = false
                return
            }
            await Task.yield()
            guard !Task.isCancelled else { return }
            focusedCommand = .openFolder
        }
        .onMoveCommand(perform: moveFocus)
        .onExitCommand(perform: onDismiss)
        .accessibilityElement(children: isPresented ? .contain : .ignore)
        .accessibilityLabel(isPresented ? "Project commands" : "")
        .accessibilityHidden(!isPresented)
    }

    private var menuShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: AtelierTheme.panelRadius,
            bottomTrailingRadius: AtelierTheme.panelRadius,
            topTrailingRadius: 0,
            style: .continuous
        )
    }

    private var commandDivider: some View {
        Divider()
            .padding(.horizontal, AtelierMetrics.spaceS)
            .padding(.vertical, AtelierMetrics.spaceXS)
    }

    private func commandButton(
        _ command: Command,
        _ title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role) {
            dismissThenPerform(action)
        } label: {
            HStack(spacing: AtelierMetrics.spaceM) {
                Image(systemName: systemImage)
                    .frame(width: AtelierMetrics.regularIconSize)
                Text(title)
                Spacer(minLength: AtelierMetrics.spaceM)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: AtelierMetrics.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(ProjectCommandRowButtonStyle(isDestructive: role == .destructive))
        .disabled(!isEnabled || isClosing)
        .focused($focusedCommand, equals: command)
        .focusEffectDisabled()
    }

    private func dismissThenPerform(_ action: @escaping () -> Void) {
        guard !isClosing else { return }
        guard !reduceMotion else {
            onDismiss()
            action()
            return
        }

        isClosing = true
        onDismiss()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(AtelierMotionTokens.deliberate))
            action()
        }
    }

    private func moveFocus(_ direction: MoveCommandDirection) {
        let commands = enabledCommands
        guard !commands.isEmpty else { return }

        let currentIndex = focusedCommand.flatMap { commands.firstIndex(of: $0) }
        switch direction {
        case .up:
            let index = currentIndex ?? 0
            focusedCommand = commands[(index - 1 + commands.count) % commands.count]
        case .down:
            focusedCommand = commands[((currentIndex ?? -1) + 1) % commands.count]
        default:
            break
        }
    }

    private var enabledCommands: [Command] {
        Command.allCases.filter { command in
            switch command {
            case .zoomIn:
                zoom.canZoomIn
            case .zoomOut:
                zoom.canZoomOut
            default:
                true
            }
        }
    }
}

private struct ProjectMenuRevealModifier: AnimatableModifier {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .visualEffect { content, geometry in
                content.offset(y: -(1 - progress) * geometry.size.height)
            }
            .mask(alignment: .top) {
                Rectangle()
                    .scaleEffect(x: 1, y: progress, anchor: .top)
            }
    }
}

private struct ProjectCommandRowButtonStyle: ButtonStyle {
    let isDestructive: Bool

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .atelierFont(size: AtelierTypography.body, weight: .medium)
            .foregroundStyle(isDestructive ? Color.red : Color.primary)
            .padding(.horizontal, AtelierMetrics.spaceM)
            .background {
                RoundedRectangle(cornerRadius: AtelierTheme.rowRadius, style: .continuous)
                    .fill(AtelierTheme.controlFill(for: interactionState(configuration)))
            }
            .contentShape(
                RoundedRectangle(cornerRadius: AtelierTheme.rowRadius, style: .continuous)
            )
            .opacity(AtelierTheme.controlOpacity(for: interactionState(configuration)))
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.985)
            .onHover { isHovering = $0 }
            .animation(
                reduceMotion ? nil : .easeOut(duration: AtelierMotionTokens.quick),
                value: isHovering
            )
            .atelierPointerCursor()
    }

    private func interactionState(_ configuration: Configuration) -> AtelierInteractionState {
        if !isEnabled { return .disabled }
        if configuration.isPressed { return .pressed }
        if isHovering { return .hovered }
        return .normal
    }
}

private struct ExplorerInlineCreationRow: View {
    let request: FileTreeCreationRequest
    let workspaceURL: URL
    let onCreate: (String) async throws -> Void
    let onCancel: () -> Void
    let onCreated: () -> Void

    @State private var name = ""
    @State private var errorMessage: String?
    @State private var creationTask: Task<Void, Never>?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AtelierMetrics.spaceXS) {
            HStack(spacing: AtelierMetrics.spaceS) {
                Image(systemName: request.kind.systemImage)
                    .atelierFont(size: AtelierTypography.label, weight: .medium)
                    .foregroundStyle(AtelierTheme.accent)
                    .frame(width: AtelierMetrics.spaceL)

                TextField(request.kind.placeholder, text: $name)
                    .textFieldStyle(.plain)
                    .atelierFont(size: AtelierTypography.body)
                    .focused($isFocused)
                    .disabled(creationTask != nil)
                    .onSubmit(submit)

                if creationTask != nil {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Text(errorMessage ?? "in \(targetLabel)")
                .atelierFont(size: AtelierTypography.micro)
                .foregroundStyle(errorMessage == nil ? Color.secondary : AtelierTheme.danger)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, AtelierMetrics.spaceS)
        .padding(.vertical, AtelierMetrics.spaceS)
        .background(AtelierTheme.accent.opacity(0.08))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(errorMessage == nil ? AtelierTheme.accent : AtelierTheme.danger)
                .frame(width: 2)
        }
        .onAppear { isFocused = true }
        .onExitCommand(perform: cancel)
        .onDisappear {
            creationTask?.cancel()
            creationTask = nil
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(request.kind.title)
    }

    private var targetLabel: String {
        let root = workspaceURL.standardizedFileURL.pathComponents
        let target = request.parentURL.standardizedFileURL.pathComponents
        guard target.starts(with: root) else { return request.parentURL.lastPathComponent }
        let relative = target.dropFirst(root.count).joined(separator: "/")
        return relative.isEmpty ? workspaceURL.lastPathComponent : relative
    }

    private func submit() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, creationTask == nil else { return }
        errorMessage = nil
        creationTask = Task { @MainActor in
            do {
                try await onCreate(cleanName)
                guard !Task.isCancelled else { return }
                onCreated()
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
                creationTask = nil
                isFocused = true
            }
        }
    }

    private func cancel() {
        creationTask?.cancel()
        creationTask = nil
        onCancel()
    }
}
