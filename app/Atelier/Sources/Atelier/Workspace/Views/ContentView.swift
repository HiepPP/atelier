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
                                .shadow(color: .black.opacity(0.14), radius: 18, x: -6)
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
                    .frame(minWidth: 220, idealWidth: 300, maxWidth: 400)
            }

            TerminalTabs(model: terminalTabs)
                .frame(minWidth: 420, idealWidth: 660)
                .layoutPriority(2)

            if !zoom.isFocusMode {
                ChangesView(
                    model: gitModel,
                    onOpenDiff: terminalTabs.openGitDiff
                )
                    .frame(minWidth: 320, idealWidth: 420, maxWidth: 540)
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
            .fill(AtelierTheme.border)
            .frame(width: 5)
            .contentShape(Rectangle())
            .overlay {
                Capsule()
                    .fill(Color.secondary.opacity(0.55))
                    .frame(width: 2, height: 36)
            }
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

            HStack(spacing: 8) {
                Color.clear
                    .frame(width: 66, height: 1)

                Spacer(minLength: 12)

                Text("\(Int((zoom.scale * 100).rounded()))%")
                    .atelierFont(size: 10.5, weight: .medium, design: .monospaced)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 42)
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
                HStack(spacing: 7) {
                    Image(systemName: "folder")
                        .atelierFont(size: 11, weight: .medium)
                        .foregroundStyle(AtelierTheme.accent)

                    Text(folderName)
                        .atelierFont(size: 11.5, weight: .semibold)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(width: 320, height: 28)
                .contentShape(
                    RoundedRectangle(cornerRadius: AtelierTheme.controlRadius)
                )
            }
            .buttonStyle(.plain)
            .background(AtelierTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: AtelierTheme.controlRadius))
            .overlay {
                RoundedRectangle(cornerRadius: AtelierTheme.controlRadius)
                    .stroke(
                        isProjectMenuPresented ? AtelierTheme.accent : AtelierTheme.border,
                        lineWidth: isProjectMenuPresented ? 1 : 0.75
                    )
            }
            .shadow(color: .black.opacity(0.04), radius: 1.5, y: 1)
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
        .padding(.horizontal, 10)
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
                .padding(.vertical, 4)

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
                .padding(.vertical, 4)

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
        .padding(8)
        .frame(width: 280)
        .background(AtelierTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: AtelierTheme.panelRadius))
        .overlay {
            RoundedRectangle(cornerRadius: AtelierTheme.panelRadius)
                .stroke(AtelierTheme.border, lineWidth: 0.75)
        }
        .shadow(color: .black.opacity(0.14), radius: 14, y: 6)
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
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Explorer")
                        .atelierFont(size: 12, weight: .semibold)
                    Text(folderName)
                        .atelierFont(size: 9.5, design: .monospaced)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
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
            .padding(.horizontal, 12)
            .frame(height: AtelierMetrics.commandBarHeight)
            .background(AtelierTheme.chrome)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(AtelierTheme.border)
                    .frame(height: 0.5)
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
        HStack(spacing: 12) {
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
        .atelierFont(size: 10.5, weight: .medium)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: AtelierMetrics.statusBarHeight)
        .background(AtelierTheme.chrome)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AtelierTheme.border)
                .frame(height: 0.5)
        }
    }
}

private struct ProjectMenuSectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .atelierFont(size: 9.5, weight: .semibold)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 8)
            .padding(.bottom, 2)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct ProjectMenuRow: View {
    let title: String
    let systemImage: String
    var isEnabled = true
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .atelierFont(size: 11, weight: .medium)
                    .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
                    .frame(width: 16)

                Text(title)
                    .atelierFont(size: 11.5)

                Spacer(minLength: 12)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: AtelierTheme.rowRadius)
                    .fill(
                        isHovering && isEnabled
                            ? AtelierTheme.accent.opacity(0.10)
                            : Color.clear
                    )
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { isHovering = $0 }
        .accessibilityLabel(title)
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
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: request.kind.systemImage)
                    .atelierFont(size: 11, weight: .medium)
                    .foregroundStyle(AtelierTheme.accent)
                    .frame(width: 14)

                TextField(request.kind.placeholder, text: $name)
                    .textFieldStyle(.plain)
                    .atelierFont(size: 12)
                    .focused($isFocused)
                    .disabled(creationTask != nil)
                    .onSubmit(submit)

                if creationTask != nil {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Text(errorMessage ?? "in \(targetLabel)")
                .atelierFont(size: 9.5)
                .foregroundStyle(errorMessage == nil ? Color.secondary : Color.red)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(AtelierTheme.accent.opacity(0.08))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(errorMessage == nil ? AtelierTheme.accent : Color.red)
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
