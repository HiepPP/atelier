import AppKit
import SwiftUI

nonisolated enum WorkspaceLayoutMode: Equatable, Sendable {
    case compact
    case standard
    case wide

    var docksExplorer: Bool { self != .compact }
    var docksSourceControl: Bool { self == .wide }
}

nonisolated enum WorkspaceLayoutPolicy {
    static let compactBreakpoint: CGFloat = 900
    static let wideBreakpoint: CGFloat = 1_280
    static let maximumOverlayWidth: CGFloat = 380

    static func mode(containerWidth: CGFloat) -> WorkspaceLayoutMode {
        if containerWidth < compactBreakpoint { return .compact }
        if containerWidth < wideBreakpoint { return .standard }
        return .wide
    }

    static func overlayWidth(containerWidth: CGFloat) -> CGFloat {
        min(
            maximumOverlayWidth,
            max(300, (containerWidth * 0.46).rounded())
        )
    }
}

struct ContentView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Group {
            if let workspace = app.workspace {
                WorkspaceView(session: workspace)
                    .id(workspace.state.id)
            } else {
                EmptyStateView()
            }
        }
        .background(AtelierTheme.canvas)
        .tint(AtelierTheme.accent)
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
                        app.chooseWorkspace()
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
    @Environment(AppModel.self) private var app
    @Environment(AtelierZoomModel.self) private var zoom
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var fileTreeCreationRequest: FileTreeCreationRequest?
    @State private var fileTreeTargetDirectory: URL?
    @State private var responderBeforeAgentPreview: NSResponder?
    @State private var responderBeforeProjectMenu: NSResponder?
    @State private var isProjectMenuPresented = false
    @State private var isExplorerDockedHidden = false
    @State private var isSourceControlDockedHidden = false
    @State private var isExplorerOverlayPresented = false
    @State private var isSourceControlOverlayPresented = false
    @FocusState private var isProjectMenuFocused: Bool

    var body: some View {
        GeometryReader { outerGeometry in
            let workspaceLayout = WorkspaceLayoutPolicy.mode(
                containerWidth: outerGeometry.size.width
            )

            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    commandBar(layout: workspaceLayout)

                    Divider()

                    GeometryReader { geometry in
                        workspaceSurface(
                            containerWidth: geometry.size.width,
                            containerHeight: geometry.size.height,
                            workspaceLayout: workspaceLayout
                        )
                    }

                    statusBar
                }

                if isProjectMenuPresented {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(perform: closeProjectMenu)
                        .accessibilityHidden(true)

                    projectMenuContent
                        .padding(.top, AtelierMetrics.commandBarHeight - 3)
                        .focusable()
                        .focused($isProjectMenuFocused)
                        .focusEffectDisabled()
                        .onAppear {
                            isProjectMenuFocused = true
                        }
                        .onExitCommand(perform: closeProjectMenu)
                        .transition(
                            .scale(scale: 0.96, anchor: .top)
                                .combined(with: .opacity)
                        )
                }
            }
            .background(AtelierTheme.editor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.container, edges: .top)
            .onExitCommand(perform: closeProjectMenu)
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

    private func workspaceColumns(layout: WorkspaceLayoutMode) -> some View {
        HSplitView {
            if !zoom.isFocusMode,
               layout.docksExplorer,
               !isExplorerDockedHidden {
                explorerColumn
                    .frame(
                        minWidth: AtelierMetrics.explorerMinWidth,
                        idealWidth: AtelierMetrics.explorerIdealWidth,
                        maxWidth: AtelierMetrics.explorerMaxWidth
                    )
            }

            TerminalTabs(model: terminalTabs)
                .frame(
                    minWidth: AtelierMetrics.centerMinWidth,
                    idealWidth: AtelierMetrics.centerIdealWidth
                )
                .layoutPriority(2)

            if !zoom.isFocusMode,
               layout.docksSourceControl,
               !isSourceControlDockedHidden {
                ChangesView(
                    model: gitModel,
                    onOpenDiff: terminalTabs.openGitDiff
                )
                    .frame(
                        minWidth: AtelierMetrics.sourceControlMinWidth,
                        idealWidth: AtelierMetrics.sourceControlIdealWidth,
                        maxWidth: AtelierMetrics.sourceControlMaxWidth
                    )
                    .layoutPriority(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .atelierSplitViewChrome()
    }

    private func workspaceSurface(
        containerWidth: CGFloat,
        containerHeight: CGFloat,
        workspaceLayout: WorkspaceLayoutMode
    ) -> some View {
        primaryWorkspace(
            containerHeight: containerHeight,
            workspaceLayout: workspaceLayout
        )
        .overlay(alignment: .leading) {
            if !zoom.isFocusMode,
               !workspaceLayout.docksExplorer,
               isExplorerOverlayPresented,
               !session.isAgentPreviewPresented {
                explorerColumn
                    .frame(width: WorkspaceLayoutPolicy.overlayWidth(containerWidth: containerWidth))
                    .atelierOverlayPanel(edge: .leading)
                    .onExitCommand {
                        isExplorerOverlayPresented = false
                    }
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .overlay(alignment: .trailing) {
            if !zoom.isFocusMode,
               !workspaceLayout.docksSourceControl,
               isSourceControlOverlayPresented,
               !session.isAgentPreviewPresented {
                ChangesView(
                    model: gitModel,
                    onOpenDiff: terminalTabs.openGitDiff,
                    onClose: {
                        withAnimation(reduceMotion ? nil : AtelierMotionTokens.panel) {
                            isSourceControlOverlayPresented = false
                        }
                    }
                )
                .frame(width: WorkspaceLayoutPolicy.overlayWidth(containerWidth: containerWidth))
                .atelierOverlayPanel(edge: .trailing)
                .onExitCommand {
                    isSourceControlOverlayPresented = false
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }

    @ViewBuilder
    private func primaryWorkspace(
        containerHeight: CGFloat,
        workspaceLayout: WorkspaceLayoutMode
    ) -> some View {
        if session.isAgentPreviewPresented {
            VSplitView {
                agentPreview
                    .frame(
                        minHeight: AgentPreviewPanePolicy.minimumHeight,
                        idealHeight: AgentPreviewPanePolicy.preferredHeight(
                            containerHeight: containerHeight
                        ),
                        maxHeight: AgentPreviewPanePolicy.maximumHeight(
                            containerHeight: containerHeight
                        )
                    )

                workspaceColumns(layout: workspaceLayout)
                    .frame(minHeight: AgentPreviewPanePolicy.workspaceMinimumHeight)
            }
        } else {
            workspaceColumns(layout: workspaceLayout)
        }
    }

    private var agentPreview: some View {
        AgentResponsesView(
            model: session.agentResponses,
            onClose: closeAgentPreview
        )
        .frame(maxHeight: .infinity)
        .environment(\.atelierZoomScale, zoom.contentScale)
        .onExitCommand(perform: closeAgentPreview)
    }

    private func openAgentPreview() {
        responderBeforeAgentPreview = app.windowController.currentFirstResponder()
        isSourceControlOverlayPresented = false
        isExplorerOverlayPresented = false
        session.openResponses()
    }

    private func closeAgentPreview() {
        session.closeAgentPreview()
        app.windowController.restoreFirstResponder(responderBeforeAgentPreview)
        responderBeforeAgentPreview = nil
    }

    private func toggleAgentPreview() {
        if session.isAgentPreviewPresented {
            closeAgentPreview()
        } else {
            openAgentPreview()
        }
    }

    private func isExplorerVisible(layout: WorkspaceLayoutMode) -> Bool {
        layout.docksExplorer ? !isExplorerDockedHidden : isExplorerOverlayPresented
    }

    private func isSourceControlVisible(layout: WorkspaceLayoutMode) -> Bool {
        layout.docksSourceControl
            ? !isSourceControlDockedHidden
            : isSourceControlOverlayPresented
    }

    private func toggleExplorer(layout: WorkspaceLayoutMode) {
        if session.isAgentPreviewPresented {
            closeAgentPreview()
        }
        isSourceControlOverlayPresented = false
        withAnimation(reduceMotion ? nil : AtelierMotionTokens.panel) {
            if layout.docksExplorer {
                isExplorerDockedHidden.toggle()
            } else {
                isExplorerOverlayPresented.toggle()
            }
        }
    }

    private func toggleSourceControl(layout: WorkspaceLayoutMode) {
        if session.isAgentPreviewPresented {
            closeAgentPreview()
        }
        isExplorerOverlayPresented = false
        withAnimation(reduceMotion ? nil : AtelierMotionTokens.panel) {
            if layout.docksSourceControl {
                isSourceControlDockedHidden.toggle()
            } else {
                isSourceControlOverlayPresented.toggle()
            }
        }
    }

    private func commandBar(layout: WorkspaceLayoutMode) -> some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    app.windowController.zoomWorkspaceWindow()
                }

            HStack(spacing: AtelierMetrics.spaceXS) {
                Color.clear
                    .frame(width: AtelierMetrics.trafficLightReserve, height: 1)

                Button {
                    toggleExplorer(layout: layout)
                } label: {
                    Image(systemName: "sidebar.leading")
                }
                .buttonStyle(
                    AtelierToolbarButtonStyle(
                        isSelected: isExplorerVisible(layout: layout)
                    )
                )
                .accessibilityLabel(
                    isExplorerVisible(layout: layout) ? "Hide Explorer" : "Show Explorer"
                )
                .help(isExplorerVisible(layout: layout) ? "Hide Explorer" : "Show Explorer")

                Button {
                    toggleSourceControl(layout: layout)
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "arrow.triangle.branch")
                        if gitModel.snapshot.status.changes.count > 0 {
                            Circle()
                                .fill(AtelierTheme.gitOrange)
                                .frame(width: 6, height: 6)
                                .offset(x: 3, y: -3)
                        }
                    }
                }
                .buttonStyle(
                    AtelierToolbarButtonStyle(
                        isSelected: isSourceControlVisible(layout: layout)
                    )
                )
                .accessibilityLabel(
                    isSourceControlVisible(layout: layout)
                        ? "Hide Source Control"
                        : "Show Source Control"
                )
                .accessibilityValue("\(gitModel.snapshot.status.changes.count) changes")
                .help(
                    isSourceControlVisible(layout: layout)
                        ? "Hide Source Control"
                        : "Show Source Control"
                )

                Spacer(minLength: AtelierMetrics.spaceM)

                Button {
                    toggleAgentPreview()
                } label: {
                    Image(systemName: "sidebar.trailing")
                        .foregroundStyle(
                            session.agentResponses.unreadCount > 0
                                ? AtelierTheme.accent
                                : Color.primary
                        )
                }
                .buttonStyle(
                    AtelierToolbarButtonStyle(isSelected: session.isAgentPreviewPresented)
                )
                .accessibilityLabel(
                    session.isAgentPreviewPresented
                        ? "Close agent preview"
                        : "Open agent preview"
                )
                .accessibilityValue("\(session.agentResponses.unreadCount) unread")
                .help(session.isAgentPreviewPresented ? "Close agent preview" : "Open agent preview")

                Button {
                    session.openGemma()
                } label: {
                    Image(systemName: "sparkles")
                }
                .buttonStyle(AtelierToolbarButtonStyle(isSelected: terminalTabs.gemmaTabCount > 0))
                .accessibilityLabel("Open Gemma workspace assistant")
                .help("Open Gemma workspace assistant")

                Button {
                    zoom.toggleFocusMode()
                } label: {
                    Image(
                        systemName: zoom.isFocusMode
                            ? "rectangle.split.3x1"
                            : "rectangle.center.inset.filled"
                    )
                }
                .buttonStyle(AtelierToolbarButtonStyle(isSelected: zoom.isFocusMode))
                .accessibilityLabel(zoom.isFocusMode ? "Exit focus mode" : "Enter focus mode")
                .help(zoom.isFocusMode ? "Exit focus mode" : "Enter focus mode")
            }

            Button {
                toggleProjectMenu()
            } label: {
                HStack(spacing: AtelierMetrics.spaceM) {
                    Image(systemName: "square.stack.3d.up")
                        .atelierFont(size: AtelierTypography.label, weight: .semibold)
                        .foregroundStyle(AtelierTheme.accent)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(folderName)
                            .atelierFont(
                                size: AtelierTypography.headline,
                                weight: .semibold,
                                design: .serif
                            )
                            .lineLimit(1)
                            .truncationMode(.middle)

                        if layout != .compact {
                            Text(
                                gitModel.snapshot.branch.isEmpty
                                    ? "Detached HEAD"
                                    : gitModel.snapshot.branch
                            )
                            .atelierFont(size: AtelierTypography.micro, design: .monospaced)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        }
                    }
                }
                .padding(.horizontal, AtelierMetrics.spaceM)
                .frame(
                    minWidth: layout == .compact ? 180 : 240,
                    idealWidth: 300,
                    maxWidth: 340,
                    minHeight: AtelierMetrics.controlHeight,
                    maxHeight: AtelierMetrics.controlHeight
                )
                .contentShape(
                    RoundedRectangle(cornerRadius: AtelierTheme.controlRadius)
                )
            }
            .buttonStyle(.plain)
            .glassEffect(
                .regular
                    .tint(isProjectMenuPresented ? AtelierTheme.accent.opacity(0.16) : nil)
                    .interactive(),
                in: RoundedRectangle(cornerRadius: AtelierTheme.controlRadius, style: .continuous)
            )
            .scaleEffect(
                reduceMotion ? 1 : (isProjectMenuPresented ? 1.012 : 1)
            )
            .animation(
                reduceMotion
                    ? nil
                    : .spring(response: 0.22, dampingFraction: 0.76),
                value: isProjectMenuPresented
            )
            .accessibilityLabel("Project commands for \(folderName)")
            .accessibilityValue(
                [
                    isProjectMenuPresented ? "Expanded" : "Collapsed",
                    gitModel.snapshot.branch.isEmpty
                        ? "No active branch"
                        : "Branch \(gitModel.snapshot.branch)"
                ].joined(separator: ", ")
            )
            .help("Project commands")
            .atelierPointerCursor()
        }
        .padding(.horizontal, AtelierMetrics.spaceM)
        .frame(height: AtelierMetrics.commandBarHeight)
        .background(AtelierTheme.chrome)
    }

    private var projectMenuContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            ProjectMenuSectionLabel(title: "Workspace")

            ProjectMenuRow(title: "Open Folder...", systemImage: "folder") {
                performProjectCommand {
                    app.chooseWorkspace()
                }
            }

            ProjectMenuRow(
                title: "Show in Finder",
                systemImage: "folder.badge.magnifyingglass"
            ) {
                performProjectCommand {
                    NSWorkspace.shared.activateFileViewerSelecting([workspaceURL])
                }
            }

            Divider()
                .padding(.vertical, AtelierMetrics.spaceXS)

            ProjectMenuSectionLabel(title: "Open")

            ProjectMenuRow(
                title: session.isAgentPreviewPresented
                    ? "Close Agent Preview"
                    : "Open Agent Preview",
                systemImage: "sidebar.trailing"
            ) {
                performProjectCommand(toggleAgentPreview)
            }

            ProjectMenuRow(title: "Open Gemma", systemImage: "sparkles") {
                performProjectCommand {
                    session.openGemma()
                }
            }

            Divider()
                .padding(.vertical, AtelierMetrics.spaceXS)

            ProjectMenuSectionLabel(title: "View")

            ProjectMenuRow(
                title: zoom.isFocusMode ? "Exit Focus Mode" : "Enter Focus Mode",
                systemImage: zoom.isFocusMode
                    ? "rectangle.split.3x1"
                    : "rectangle.center.inset.filled"
            ) {
                performProjectCommand {
                    zoom.toggleFocusMode()
                }
            }

            ProjectMenuRow(
                title: "Zoom In",
                systemImage: "plus.magnifyingglass",
                isEnabled: zoom.canZoomIn
            ) {
                performProjectCommand {
                    app.windowController.maximizeWorkspaceWindow()
                    zoom.zoomIn()
                }
            }

            ProjectMenuRow(
                title: "Zoom Out",
                systemImage: "minus.magnifyingglass",
                isEnabled: zoom.canZoomOut
            ) {
                performProjectCommand {
                    zoom.zoomOut()
                }
            }

            ProjectMenuRow(title: "Actual Size", systemImage: "1.magnifyingglass") {
                performProjectCommand {
                    zoom.reset()
                }
            }
        }
        .padding(AtelierMetrics.spaceS)
        .frame(width: AtelierMetrics.projectMenuWidth)
        .background(AtelierTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: AtelierTheme.panelRadius))
        .overlay {
            RoundedRectangle(cornerRadius: AtelierTheme.panelRadius)
                .stroke(AtelierTheme.border, lineWidth: AtelierTheme.strokeControl)
        }
        .shadow(
            color: AtelierTheme.shadowFloating,
            radius: AtelierMetrics.spaceL,
            y: AtelierMetrics.spaceS
        )
    }

    private func toggleProjectMenu() {
        if !isProjectMenuPresented {
            responderBeforeProjectMenu = app.windowController.currentFirstResponder()
        }
        withAnimation(projectMenuAnimation) {
            isProjectMenuPresented.toggle()
        }
        if !isProjectMenuPresented {
            restoreProjectMenuResponder()
        }
    }

    private func closeProjectMenu() {
        guard isProjectMenuPresented else { return }
        withAnimation(projectMenuAnimation) {
            isProjectMenuPresented = false
        }
        restoreProjectMenuResponder()
    }

    private func performProjectCommand(_ action: () -> Void) {
        closeProjectMenu()
        action()
    }

    private var projectMenuAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.76)
    }

    private func restoreProjectMenuResponder() {
        isProjectMenuFocused = false
        app.windowController.restoreFirstResponder(responderBeforeProjectMenu)
        responderBeforeProjectMenu = nil
    }

    private var explorerColumn: some View {
        VStack(spacing: 0) {
            AtelierPanelHeader(title: "Explorer", subtitle: folderName) {
                HStack(spacing: AtelierMetrics.spaceXS) {
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
                }
            }
            .environment(\.atelierZoomScale, zoom.sidebarScale)

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
                onSelect: terminalTabs.openFile
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

private struct ProjectMenuSectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .atelierFont(size: AtelierTypography.micro, weight: .semibold)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, AtelierMetrics.spaceS)
            .padding(.bottom, AtelierMetrics.spaceXS)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct ProjectMenuRow: View {
    let title: String
    let systemImage: String
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AtelierMetrics.spaceS) {
                Image(systemName: systemImage)
                    .atelierFont(size: AtelierTypography.label, weight: .medium)
                    .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
                    .frame(width: AtelierMetrics.spaceL)

                Text(title)
                    .atelierFont(size: AtelierTypography.label)

                Spacer(minLength: AtelierMetrics.spaceM)
            }
            .padding(.horizontal, AtelierMetrics.spaceS)
            .frame(maxWidth: .infinity)
            .frame(height: AtelierMetrics.controlHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(AtelierMenuRowButtonStyle())
        .disabled(!isEnabled)
        .accessibilityLabel(title)
    }
}

private struct AtelierMenuRowButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: AtelierTheme.rowRadius, style: .continuous)
                    .fill(AtelierTheme.controlFill(for: interactionState(configuration)))
            }
            .opacity(AtelierTheme.controlOpacity(for: interactionState(configuration)))
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.99)
            .onHover { isHovering = $0 }
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
