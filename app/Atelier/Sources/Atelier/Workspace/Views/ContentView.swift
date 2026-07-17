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
        .preferredColorScheme(.light)
    }
}

/// Empty state: chưa có workspace.
struct EmptyStateView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack(alignment: .topTrailing) {
            AtelierTheme.canvas

            Circle()
                .fill(AtelierTheme.accent.opacity(0.09))
                .frame(width: 360, height: 360)
                .offset(x: 120, y: -150)
                .accessibilityHidden(true)

            HStack(alignment: .center, spacing: 64) {
                VStack(alignment: .leading, spacing: 20) {
                    Text("ATELIER")
                        .atelierFont(size: 11, weight: .bold, design: .monospaced)
                        .tracking(2.4)
                        .foregroundStyle(AtelierTheme.accent)

                    Text("Chưa mở workspace")
                        .atelierFont(size: 38, weight: .semibold)
                        .tracking(-1.4)

                    Text("Chọn một folder để xem changes, đọc file và chạy terminal.")
                        .atelierFont(size: 14)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 360, alignment: .leading)

                    Button {
                        app.chooseWorkspace()
                    } label: {
                        Label("Mở Folder", systemImage: "arrow.up.right")
                    }
                    .buttonStyle(AtelierLuminarePrimaryButtonStyle())
                    .keyboardShortcut("o", modifiers: .command)
                }

                Spacer(minLength: 0)

                Image(systemName: "folder")
                    .atelierFont(size: 116, weight: .ultraLight)
                    .foregroundStyle(AtelierTheme.accent.opacity(0.72))
                    .frame(width: 230, height: 230)
                    .background(AtelierTheme.panel)
                    .clipShape(RoundedRectangle(cornerRadius: AtelierTheme.panelRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: AtelierTheme.panelRadius, style: .continuous)
                            .stroke(AtelierTheme.border, lineWidth: 1)
                    }
                    .accessibilityHidden(true)
            }
            .padding(48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct WorkspaceView: View {
    let session: WorkspaceSession
    @Environment(AppModel.self) private var app
    @Environment(AtelierZoomModel.self) private var zoom
    @State private var fileTreeCreationRequest: FileTreeCreationRequest?
    @State private var fileTreeTargetDirectory: URL?
    @State private var agentPreviewWidth: CGFloat = 448
    @State private var agentPreviewDragStartWidth: CGFloat?
    @State private var responderBeforeAgentPreview: NSResponder?

    var body: some View {
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
        .background(AtelierTheme.editor)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        HStack(spacing: 8) {
            Color.clear
                .frame(width: 66, height: 1)

            Image(systemName: "chevron.left")
            Image(systemName: "chevron.right")
                .opacity(0.35)
            Spacer(minLength: 18)

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .atelierFont(size: 10, weight: .medium)
                    .foregroundStyle(.secondary)
                Text(folderName)
                    .atelierFont(size: 11.5, weight: .medium)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: 720)
            .frame(height: 28)
            .background(AtelierTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(AtelierTheme.border, lineWidth: 0.75)
            }

            Spacer(minLength: 18)

            Text("\(Int((zoom.scale * 100).rounded()))%")
                .atelierFont(size: 10.5, weight: .medium, design: .monospaced)
                .foregroundStyle(.secondary)
                .frame(minWidth: 42)
                .frame(height: 24)
                .background(AtelierTheme.panel)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(AtelierTheme.border, lineWidth: 0.75)
                }
                .accessibilityLabel("Zoom level")
                .accessibilityValue("\(Int((zoom.scale * 100).rounded())) percent")
                .help("Zoom level")

            Button {
                app.chooseWorkspace()
            } label: {
                Image(systemName: "folder.badge.gearshape")
            }
            .buttonStyle(AtelierLuminareIconButtonStyle())
            .help("Change folder")

            Button {
                toggleAgentPreview()
            } label: {
                Image(systemName: "text.bubble")
                    .overlay(alignment: .topTrailing) {
                        if session.agentResponses.unreadCount > 0 {
                            Circle()
                                .fill(AtelierTheme.gitOrange)
                                .frame(width: 5, height: 5)
                                .offset(x: 3, y: -2)
                        }
                    }
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
            .help(zoom.isFocusMode ? "Exit focus mode" : "Enter focus mode")

            Image(systemName: "gearshape")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: 40)
        .background(AtelierTheme.chrome)
        .onTapGesture(count: 2) {
            app.windowController.zoomWorkspaceWindow()
        }
        .atelierPointerCursor()
    }

    private var explorerColumn: some View {
        VStack(spacing: 0) {
            explorerActivityBar

            HStack {
                Text(folderName.uppercased())
                    .atelierFont(size: 10, weight: .medium)
                    .foregroundStyle(.secondary)
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
                .help("New folder")
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
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

    private var explorerActivityBar: some View {
        HStack(spacing: 2) {
            ForEach(
                ["doc.on.doc", "magnifyingglass", "square.grid.2x2", "point.3.connected.trianglepath.dotted", "arrow.triangle.branch"],
                id: \.self
            ) { icon in
                Image(systemName: icon)
                    .atelierFont(size: 13)
                    .foregroundStyle(icon == "doc.on.doc" ? Color.primary : Color.secondary)
                    .frame(width: 30, height: 40)
                    .overlay(alignment: .bottom) {
                        if icon == "doc.on.doc" {
                            Rectangle()
                                .fill(AtelierTheme.gitOrange)
                                .frame(height: 1.5)
                        }
                    }
            }
            Spacer()
        }
        .padding(.horizontal, 4)
        .background(AtelierTheme.chrome)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AtelierTheme.border)
                .frame(height: 0.5)
        }
        .accessibilityHidden(true)
    }

    private var statusBar: some View {
        HStack(spacing: 14) {
            Label(folderName, systemImage: "macwindow")
            Label(
                gitModel.snapshot.branch.isEmpty ? "detached" : gitModel.snapshot.branch,
                systemImage: "arrow.triangle.branch"
            )
            Spacer()
            if zoom.isFocusMode {
                Text("Focus")
            }
            Text("\(Int((zoom.scale * 100).rounded()))%")
            Text("Terminal")
            if !zoom.isFocusMode {
                Text("Explorer")
                Text("Git")
            }
        }
        .atelierFont(size: 10.5, weight: .medium)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(AtelierTheme.chrome)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AtelierTheme.border)
                .frame(height: 0.5)
        }
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
