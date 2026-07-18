import AppKit
import SwiftUI

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

/// Empty state: chưa có workspace.
struct EmptyStateView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ContentUnavailableView {
            Label("Chưa mở workspace", systemImage: "folder")
                .foregroundStyle(AtelierTheme.accent)
        } description: {
            Text("Chọn một folder để xem Git, đọc file và chạy terminal.")
        } actions: {
            Button {
                app.chooseWorkspace()
            } label: {
                Text("Mở Folder")
            }
            .buttonStyle(AtelierLuminarePrimaryButtonStyle())
            .keyboardShortcut("o", modifiers: .command)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AtelierTheme.canvas)
    }
}

struct WorkspaceView: View {
    let session: WorkspaceSession
    @Environment(AppModel.self) private var app
    @Environment(AtelierZoomModel.self) private var zoom
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var fileTreeCreationRequest: FileTreeCreationRequest?
    @State private var fileTreeTargetDirectory: URL?
    @State private var agentPreviewWidth: CGFloat = 448
    @State private var agentPreviewDragStartWidth: CGFloat?
    @State private var responderBeforeAgentPreview: NSResponder?
    @State private var responderBeforeProjectMenu: NSResponder?
    @State private var isProjectMenuPresented = false
    @State private var isProjectButtonHovered = false
    @State private var isAgentResizeHandleHovered = false
    @FocusState private var isProjectMenuFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                commandBar

                Divider()

                GeometryReader { geometry in
                    let layout = AgentPreviewLayoutPolicy.layout(
                        containerWidth: geometry.size.width
                    )
                    HStack(spacing: 0) {
                        workspaceColumns

                        if session.isAgentPreviewPresented, layout == .docked {
                            agentPreviewResizeHandle(containerWidth: geometry.size.width)
                            agentPreview
                                .frame(
                                    width: AgentPreviewLayoutPolicy.clampedDockedWidth(
                                        agentPreviewWidth,
                                        containerWidth: geometry.size.width
                                    )
                                )
                        }
                    }
                    .overlay(alignment: .trailing) {
                        if session.isAgentPreviewPresented, layout == .overlay {
                            agentPreview
                                .frame(
                                    width: AgentPreviewLayoutPolicy.panelWidth(
                                        containerWidth: geometry.size.width,
                                        layout: layout
                                    )
                                )
                                .shadow(
                                    color: AtelierTheme.shadowFloating,
                                    radius: AtelierMetrics.spaceL,
                                    x: -AtelierMetrics.spaceS
                                )
                        }
                    }
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

    private var state: WorkspaceState { session.state }
    private var terminalTabs: TerminalTabsModel { session.terminalTabs }
    private var gitModel: GitWorkspaceModel { session.gitModel }

    private var folderName: String {
        (state.path as NSString).lastPathComponent
    }

    private var workspaceURL: URL {
        URL(fileURLWithPath: state.path, isDirectory: true)
    }

    private var workspaceColumns: some View {
        HSplitView {
            if !zoom.isFocusMode {
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

            if !zoom.isFocusMode {
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

    private var agentPreview: some View {
        AgentResponsesView(
            model: session.agentResponses,
            onClose: closeAgentPreview
        )
        .frame(maxHeight: .infinity)
        .environment(\.atelierZoomScale, zoom.contentScale)
    }

    private func agentPreviewResizeHandle(containerWidth: CGFloat) -> some View {
        Rectangle()
            .fill(
                isAgentResizeHandleHovered
                    ? AtelierTheme.controlFill(for: .hovered)
                    : AtelierTheme.border
            )
            .frame(width: AtelierMetrics.spaceS)
            .contentShape(Rectangle())
            .overlay {
                Capsule()
                    .fill(
                        isAgentResizeHandleHovered
                            ? AtelierTheme.accent
                            : Color.secondary.opacity(0.55)
                    )
                    .frame(width: 2, height: 36)
            }
            .onHover { isAgentResizeHandleHovered = $0 }
            .help("Drag to resize agent preview")
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let start = agentPreviewDragStartWidth ?? agentPreviewWidth
                        if agentPreviewDragStartWidth == nil {
                            agentPreviewDragStartWidth = start
                        }
                        agentPreviewWidth = AgentPreviewLayoutPolicy.clampedDockedWidth(
                            start - value.translation.width,
                            containerWidth: containerWidth
                        )
                    }
                    .onEnded { _ in
                        agentPreviewDragStartWidth = nil
                    }
            )
            .accessibilityElement()
            .accessibilityLabel("Resize agent preview")
            .accessibilityValue("\(Int(agentPreviewWidth.rounded())) points wide")
            .accessibilityAdjustableAction { direction in
                let delta: CGFloat = direction == .increment ? 24 : -24
                agentPreviewWidth = AgentPreviewLayoutPolicy.clampedDockedWidth(
                    agentPreviewWidth + delta,
                    containerWidth: containerWidth
                )
            }
    }

    private func openAgentPreview() {
        responderBeforeAgentPreview = app.windowController.currentFirstResponder()
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

    private var commandBar: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    app.windowController.zoomWorkspaceWindow()
                }

            HStack(spacing: AtelierMetrics.spaceS) {
                Color.clear
                    .frame(width: AtelierMetrics.trafficLightReserve, height: 1)

                Spacer(minLength: AtelierMetrics.spaceM)

                Text("\(Int((zoom.scale * 100).rounded()))%")
                    .atelierFont(
                        size: AtelierTypography.caption,
                        weight: .medium,
                        design: .monospaced
                    )
                    .foregroundStyle(.secondary)
                    .frame(minWidth: AtelierMetrics.zoomLabelMinWidth)
                    .accessibilityLabel("Zoom level")
                    .accessibilityValue("\(Int((zoom.scale * 100).rounded())) percent")
                    .help("Zoom level")

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
                .buttonStyle(AtelierLuminareIconButtonStyle())
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
                .buttonStyle(AtelierLuminareIconButtonStyle())
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
                .buttonStyle(AtelierLuminareIconButtonStyle())
                .accessibilityLabel(zoom.isFocusMode ? "Exit focus mode" : "Enter focus mode")
                .help(zoom.isFocusMode ? "Exit focus mode" : "Enter focus mode")
            }

            Button {
                toggleProjectMenu()
            } label: {
                HStack(spacing: AtelierMetrics.spaceS) {
                    Image(systemName: "folder")
                        .atelierFont(size: AtelierTypography.label, weight: .medium)
                        .foregroundStyle(AtelierTheme.accent)

                    Text(folderName)
                        .atelierFont(size: AtelierTypography.label, weight: .semibold)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, AtelierMetrics.spaceM)
                .frame(
                    minWidth: 240,
                    idealWidth: 320,
                    maxWidth: 360,
                    minHeight: AtelierMetrics.controlHeight,
                    maxHeight: AtelierMetrics.controlHeight
                )
                .contentShape(
                    RoundedRectangle(cornerRadius: AtelierTheme.controlRadius)
                )
            }
            .buttonStyle(.plain)
            .background(
                isProjectMenuPresented
                    ? AtelierTheme.controlFill(for: .selected)
                    : (isProjectButtonHovered
                        ? AtelierTheme.controlFill(for: .hovered)
                        : AtelierTheme.panel)
            )
            .clipShape(RoundedRectangle(cornerRadius: AtelierTheme.controlRadius))
            .overlay {
                RoundedRectangle(cornerRadius: AtelierTheme.controlRadius)
                    .stroke(
                        AtelierTheme.controlStroke(
                            for: isProjectMenuPresented ? .selected : .normal
                        ),
                        lineWidth: isProjectMenuPresented
                            ? AtelierTheme.strokeFocus
                            : AtelierTheme.strokeControl
                    )
            }
            .shadow(color: AtelierTheme.shadowSoft, radius: 2, y: 1)
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
            .onHover { isProjectButtonHovered = $0 }
            .atelierPointerCursor()
        }
        .padding(.horizontal, AtelierMetrics.spaceM)
        .frame(height: AtelierMetrics.commandBarHeight)
        .background(AtelierTheme.chrome)
        .atelierPointerCursor()
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
