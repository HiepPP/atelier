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

nonisolated enum WorkspaceSidebarTab: String, CaseIterable, Identifiable, Sendable {
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

nonisolated enum WorkspaceLayoutPolicy {
    static let compactBreakpoint: CGFloat = 900
    static let wideBreakpoint: CGFloat = 1_280

    static func mode(containerWidth: CGFloat) -> WorkspaceLayoutMode {
        if containerWidth < compactBreakpoint { return .compact }
        if containerWidth < wideBreakpoint { return .standard }
        return .wide
    }

}

nonisolated struct WorkspacePanelPresentation: Equatable, Sendable {
    var showsSidebar: Bool
    var showsInspector: Bool
    var restoresSidebarAfterInspector: Bool

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
}

struct ContentView: View {
    @Environment(AppModel.self) private var app
    @State private var commandPaletteModel = AtelierPaletteModel()
    @State private var presentedPaletteMode: AtelierPaletteMode?
    @State private var responderBeforePalette: NSResponder?

    var body: some View {
        ZStack(alignment: .top) {
            HStack(spacing: 0) {
                WorkspaceRailView()

                ZStack {
                    ForEach(app.liveSessions, id: \.state.id) { workspace in
                        let isActive = workspace.state.id == app.selectedWorkspaceID
                        WorkspaceView(session: workspace, isActive: isActive)
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
        }
        .background(AtelierTheme.canvas)
        .tint(AtelierTheme.accent)
        .focusedSceneValue(\.showQuickOpen, quickOpenAction)
        .focusedSceneValue(\.showCommandPalette) {
            presentPalette(.commands)
        }
        .onChange(of: app.selectedWorkspaceID) { _, _ in
            if presentedPaletteMode != nil {
                dismissPalette(restoresResponder: false)
            }
        }
    }

    private var quickOpenAction: (() -> Void)? {
        guard app.workspace != nil else { return nil }
        return { presentPalette(.files) }
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

    private func presentPalette(_ mode: AtelierPaletteMode) {
        responderBeforePalette = app.windowController.currentFirstResponder()
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
        dismissPalette(restoresResponder: false)
        switch selection {
        case .file(let url):
            app.workspace?.terminalTabs.openFile(url)
        case .action(let action):
            let context = AtelierActionRegistry.context(for: app)
            guard AtelierActionRegistry.isEnabled(action, context: context) else { return }
            AtelierActionRegistry.perform(action, model: app)
        }
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
    @Environment(AppModel.self) private var app
    @Environment(AtelierZoomModel.self) private var zoom
    @State private var fileTreeCreationRequest: FileTreeCreationRequest?
    @State private var fileTreeTargetDirectory: URL?
    @State private var responderBeforeAgentPreview: NSResponder?
    @State private var selectedSidebarTab = WorkspaceSidebarTab.explorer
    @State private var panels = WorkspacePanelPresentation.initial(for: .standard)
    @State private var panelsBeforeFocus = WorkspacePanelPresentation.initial(for: .standard)
    @State private var responderBeforeInspector: NSResponder?
    @State private var hasAppliedInitialLayout = false
    @State private var currentLayoutMode = WorkspaceLayoutMode.standard

    var body: some View {
        GeometryReader { outerGeometry in
            let workspaceLayout = WorkspaceLayoutPolicy.mode(
                containerWidth: outerGeometry.size.width
            )

            VStack(spacing: 0) {
                workspaceSurface
                statusBar
            }
            .background(AtelierTheme.editor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                if isActive {
                    workspaceToolbar
                }
            }
            .navigationTitle(isActive ? folderName : "")
            .onAppear {
                applyInitialLayout(workspaceLayout)
            }
            .onChange(of: workspaceLayout) { oldLayout, newLayout in
                adaptPanels(from: oldLayout, to: newLayout)
            }
            .onChange(of: zoom.isFocusMode) { _, isFocused in
                updateFocusMode(isFocused)
            }
        }
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
        HSplitView {
            if panels.showsSidebar, !zoom.isFocusMode {
                workspaceSidebar
                    .frame(
                        minWidth: AtelierMetrics.workspaceSidebarMinWidth,
                        idealWidth: AtelierMetrics.workspaceSidebarIdealWidth,
                        maxWidth: AtelierMetrics.workspaceSidebarMaxWidth
                    )
            }

            workspaceDetail

            if panels.showsInspector, !zoom.isFocusMode {
                WorkspaceInspectorView(context: terminalTabs.selectedInspectorContext)
                    .frame(
                        minWidth: AtelierMetrics.inspectorMinWidth,
                        idealWidth: AtelierMetrics.inspectorIdealWidth,
                        maxWidth: AtelierMetrics.inspectorMaxWidth
                    )
                    .layoutPriority(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .atelierSplitViewChrome()
    }

    private var workspaceDetail: some View {
        TerminalTabs(
            model: terminalTabs,
            agentResponses: session.agentResponses,
            isAgentSidecarPresented: session.isAgentSidecarPresented,
            onOpenAgentSidecar: openAgentSidecar,
            onCloseAgentSidecar: closeAgentSidecar
        )
        .frame(
            minWidth: AtelierMetrics.centerMinWidth,
            idealWidth: AtelierMetrics.centerIdealWidth
        )
        .layoutPriority(2)
    }

    private func openAgentSidecar() {
        responderBeforeAgentPreview = app.windowController.currentFirstResponder()
        Task { @MainActor in
            await Task.yield()
            session.openAgentSidecar()
        }
    }

    private func closeAgentSidecar() {
        Task { @MainActor in
            await Task.yield()
            session.closeAgentSidecar()
            app.windowController.restoreFirstResponder(responderBeforeAgentPreview)
            responderBeforeAgentPreview = nil
        }
    }

    @ToolbarContentBuilder
    private var workspaceToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                panels = panels.togglingSidebar(layout: currentLayoutMode)
            } label: {
                Image(systemName: "sidebar.leading")
            }
            .accessibilityLabel(panels.showsSidebar ? "Hide Sidebar" : "Show Sidebar")
            .help(panels.showsSidebar ? "Hide Sidebar" : "Show Sidebar")
            .disabled(zoom.isFocusMode || !currentLayoutMode.docksSidebar)
            .atelierPointerCursor()
        }

        ToolbarItem(placement: .principal) {
            Menu {
                Button("Open Folder...", systemImage: "folder") {
                    AtelierActionRegistry.perform(.openFolder, model: app)
                }
                Button("Show in Finder", systemImage: "folder.badge.magnifyingglass") {
                    NSWorkspace.shared.activateFileViewerSelecting([workspaceURL])
                }
                Button("Copy Project Path", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(state.path, forType: .string)
                }
                Divider()
                Button("New Terminal", systemImage: "terminal") {
                    AtelierActionRegistry.perform(.newTerminal, model: app)
                }
                Button("Open Gemma", systemImage: "sparkles") {
                    session.openGemma()
                }
                Button("Close Workspace", systemImage: "xmark.rectangle", role: .destructive) {
                    app.closeWorkspace(id: state.id)
                }
                Divider()
                Button("Zoom In", systemImage: "plus.magnifyingglass") {
                    app.windowController.maximizeWorkspaceWindow()
                    zoom.zoomIn()
                }
                .disabled(!zoom.canZoomIn)
                Button("Zoom Out", systemImage: "minus.magnifyingglass") {
                    zoom.zoomOut()
                }
                .disabled(!zoom.canZoomOut)
                Button("Actual Size", systemImage: "1.magnifyingglass") {
                    zoom.reset()
                }
            } label: {
                ProjectMenuLabel(projectName: folderName)
            }
            .menuStyle(.borderlessButton)
            .frame(width: AtelierMetrics.projectMenuWidth)
            .help("\(folderName)\n\(state.path)\nProject commands")
            .accessibilityLabel("Project commands for \(folderName)")
            .atelierPointerCursor()
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                session.openGemma()
            } label: {
                Image(systemName: "sparkles")
            }
            .accessibilityLabel("Open Gemma workspace assistant")
            .help("Open Gemma workspace assistant")
            .atelierPointerCursor()

            Button {
                zoom.toggleFocusMode()
            } label: {
                Image(
                    systemName: zoom.isFocusMode
                        ? "rectangle.split.3x1"
                        : "rectangle.center.inset.filled"
                )
            }
            .accessibilityLabel(zoom.isFocusMode ? "Exit focus mode" : "Enter focus mode")
            .help(zoom.isFocusMode ? "Exit focus mode" : "Enter focus mode")
            .atelierPointerCursor()

            Button {
                toggleInspector()
            } label: {
                Image(systemName: "sidebar.trailing")
            }
            .accessibilityLabel(panels.showsInspector ? "Hide inspector" : "Show inspector")
            .help(panels.showsInspector ? "Hide Inspector" : "Show Inspector")
            .disabled(zoom.isFocusMode || !currentLayoutMode.supportsInspector)
            .atelierPointerCursor()
        }
    }

    private func applyInitialLayout(_ layout: WorkspaceLayoutMode) {
        guard !hasAppliedInitialLayout else { return }
        hasAppliedInitialLayout = true
        currentLayoutMode = layout
        panels = .initial(for: layout)
    }

    private func adaptPanels(
        from oldLayout: WorkspaceLayoutMode,
        to newLayout: WorkspaceLayoutMode
    ) {
        currentLayoutMode = newLayout
        guard !zoom.isFocusMode else { return }
        panels = panels.adapting(from: oldLayout, to: newLayout)
    }

    private func updateFocusMode(_ isFocused: Bool) {
        if isFocused {
            panelsBeforeFocus = panels
            panels = .initial(for: .compact)
        } else {
            panels = panelsBeforeFocus
        }
    }

    private func toggleInspector() {
        guard currentLayoutMode.supportsInspector else { return }
        responderBeforeInspector = app.windowController.currentFirstResponder()
        panels = panels.togglingInspector(layout: currentLayoutMode)
        Task { @MainActor in
            await Task.yield()
            restoreInspectorResponder()
        }
    }

    private func restoreInspectorResponder() {
        app.windowController.restoreFirstResponder(responderBeforeInspector)
        responderBeforeInspector = nil
    }

    private var workspaceSidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: AtelierMetrics.spaceXS) {
                ForEach(WorkspaceSidebarTab.allCases) { tab in
                    Button {
                        selectedSidebarTab = tab
                    } label: {
                        HStack(spacing: AtelierMetrics.spaceXS) {
                            Image(systemName: tab.systemImage)
                            Text(tab.rawValue)
                            if tab == .sourceControl,
                               gitModel.snapshot.status.changes.count > 0 {
                                AtelierCountBadge(
                                    value: gitModel.snapshot.status.changes.count,
                                    color: AtelierTheme.gitOrange
                                )
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: AtelierMetrics.sectionHeaderHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .atelierPointerCursor()
                    .foregroundStyle(
                        selectedSidebarTab == tab ? Color.primary : Color.secondary
                    )
                    .background(
                        selectedSidebarTab == tab
                            ? AtelierTheme.selection
                            : Color.clear
                    )
                    .overlay(alignment: .bottom) {
                        if selectedSidebarTab == tab {
                            Rectangle()
                                .fill(AtelierTheme.accent)
                                .frame(height: 2)
                        }
                    }
                    .accessibilityValue(selectedSidebarTab == tab ? "Selected" : "Not selected")
                }

                if selectedSidebarTab == .explorer {
                    Button {
                        fileTreeCreationRequest = FileTreeCreationRequest(
                            kind: .file,
                            parentURL: fileTreeTargetDirectory ?? workspaceURL
                        )
                    } label: {
                        Image(systemName: "doc.badge.plus")
                    }
                    .buttonStyle(AtelierLuminareIconButtonStyle())
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
                    .buttonStyle(AtelierLuminareIconButtonStyle())
                    .accessibilityLabel("New folder")
                    .help("New folder")
                } else {
                    Button {
                        gitModel.refresh()
                    } label: {
                        if gitModel.isLoading {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(AtelierLuminareIconButtonStyle())
                    .accessibilityLabel("Refresh Git status")
                    .help("Refresh Git status")
                }
            }
            .padding(.horizontal, AtelierMetrics.spaceS)
            .frame(height: AtelierMetrics.panelHeaderHeight)
            .background(AtelierTheme.chrome)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(AtelierTheme.border)
                    .frame(height: AtelierTheme.strokeHairline)
            }
            .environment(\.atelierZoomScale, zoom.sidebarScale)

            switch selectedSidebarTab {
            case .explorer:
                explorerContent
            case .sourceControl:
                ChangesView(
                    model: gitModel,
                    onOpenDiff: terminalTabs.openGitDiff,
                    showsPanelHeader: false
                )
            }
        }
        .background(AtelierTheme.sidebar)
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

            FileTreeView(
                rootURL: workspaceURL,
                revision: session.fileTreeRevision,
                onTargetDirectoryChange: { fileTreeTargetDirectory = $0 },
                onCreateItem: { kind, parentURL in
                    fileTreeCreationRequest = FileTreeCreationRequest(
                        kind: kind,
                        parentURL: parentURL
                    )
                },
                onPreview: terminalTabs.previewFile,
                onOpen: terminalTabs.openFile
            )
            .environment(\.atelierZoomScale, zoom.sidebarScale)
        }
        .background(AtelierTheme.sidebar)
    }

    private var statusBar: some View {
        HStack(spacing: AtelierMetrics.spaceM) {
            Label(
                gitModel.snapshot.branch.isEmpty ? "detached" : gitModel.snapshot.branch,
                systemImage: "arrow.triangle.branch"
            )
            Spacer()
            if zoom.isFocusMode {
                Text("Focus")
            }
            Text("\(Int((zoom.scale * 100).rounded()))%")
        }
        .atelierFont(size: AtelierTypography.caption, weight: .medium)
        .foregroundStyle(.secondary)
        .padding(.horizontal, AtelierMetrics.spaceM)
        .frame(height: AtelierMetrics.statusBarHeight)
        .background(AtelierTheme.chrome)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AtelierTheme.border)
                .frame(height: AtelierTheme.strokeHairline)
        }
    }
}

private struct ProjectMenuLabel: View {
    let projectName: String

    var body: some View {
        HStack(spacing: AtelierMetrics.spaceS) {
            Image(systemName: "folder")
                .atelierFont(size: AtelierTypography.body, weight: .medium)
                .foregroundStyle(.secondary)

            Text(projectName)
                .atelierFont(size: AtelierTypography.body, weight: .semibold)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: AtelierMetrics.spaceM)

            Image(systemName: "chevron.down")
                .atelierFont(size: AtelierTypography.micro, weight: .medium)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, AtelierMetrics.spaceM)
        .frame(maxWidth: .infinity)
        .frame(minHeight: AtelierMetrics.controlHeight)
        .contentShape(Rectangle())
    }
}

private struct WorkspaceInspectorView: View {
    let context: TerminalTabInspectorContext?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Group {
            if let context {
                ScrollView {
                    VStack(alignment: .leading, spacing: AtelierMetrics.spaceL) {
                        inspectorHeader(context)

                        Divider()

                        VStack(spacing: 0) {
                            ForEach(Array(context.details.enumerated()), id: \.offset) { index, detail in
                                inspectorRow(detail)
                                if index < context.details.count - 1 {
                                    Divider()
                                }
                            }
                        }
                    }
                    .padding(AtelierMetrics.spaceL)
                }
            } else {
                AtelierEmptyState(
                    systemImage: "sidebar.trailing",
                    title: "Inspector",
                    message: "Open a tab to inspect its context."
                )
            }
        }
        .background(AtelierTheme.panel)
        .accessibilityLabel("Workspace inspector")
    }

    private func inspectorHeader(_ context: TerminalTabInspectorContext) -> some View {
        HStack(alignment: .top, spacing: AtelierMetrics.spaceM) {
            ZStack {
                RoundedRectangle(cornerRadius: AtelierTheme.rowRadius, style: .continuous)
                    .fill(AtelierTheme.accent.opacity(contrast == .increased ? 0.18 : 0.10))
                Image(systemName: context.systemImage)
                    .atelierFont(size: AtelierTypography.uiSize, weight: .medium)
                    .foregroundStyle(AtelierTheme.accent)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(context.title)
                    .atelierFont(size: AtelierTypography.uiSize, weight: .semibold)
                    .lineLimit(2)
                    .truncationMode(.middle)

                HStack(spacing: AtelierMetrics.spaceXS) {
                    if context.showsActivity {
                        Image(systemName: "circle.fill")
                            .atelierFont(size: 7)
                            .foregroundStyle(AtelierTheme.accent)
                            .symbolEffect(
                                .pulse,
                                options: .repeating,
                                isActive: !reduceMotion
                            )
                            .accessibilityHidden(true)
                    }
                    Text("\(context.kind.rawValue) - \(context.status)")
                        .atelierFont(size: AtelierTypography.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(context.kind.rawValue), \(context.title), \(context.status)")
    }

    private func inspectorRow(_ detail: TerminalTabInspectorDetail) -> some View {
        VStack(alignment: .leading, spacing: AtelierMetrics.spaceXS) {
            Text(detail.label)
                .atelierFont(size: AtelierTypography.caption, weight: .medium)
                .foregroundStyle(.secondary)
            Text(detail.value)
                .atelierFont(
                    size: AtelierTypography.label,
                    design: detail.label == "Path" || detail.label == "Working directory"
                        ? .monospaced
                        : .default
                )
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, AtelierMetrics.spaceS)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(detail.label): \(detail.value)")
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
