import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: WorkspaceStore

    var body: some View {
        Group {
            if let ws = store.current {
                WorkspaceView(state: ws)
                    .id(ws.path)
            } else {
                EmptyStateView()
            }
        }
        .background(AtelierTheme.canvas)
        .tint(AtelierTheme.accent)
        .preferredColorScheme(.light)
        .atelierWindowChrome()
    }
}

/// Empty state: chưa có workspace.
struct EmptyStateView: View {
    @EnvironmentObject var store: WorkspaceStore

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
                        if let state = OpenFolder.pick() {
                            store.setWorkspace(state)
                        }
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
    let state: WorkspaceState
    @EnvironmentObject var store: WorkspaceStore
    @EnvironmentObject private var zoom: AtelierZoomModel
    @StateObject private var terminalTabs: TerminalTabsModel
    @StateObject private var gitModel: GitWorkspaceModel
    @State private var fileWatcher: FileWatcher?

    init(state: WorkspaceState) {
        self.state = state
        _terminalTabs = StateObject(wrappedValue: TerminalTabsModel(workspacePath: state.path))
        _gitModel = StateObject(wrappedValue: GitWorkspaceModel(workspacePath: state.path))
    }

    var body: some View {
        VStack(spacing: 0) {
            commandBar

            Divider()

            HSplitView {
                if !zoom.isFocusMode {
                    explorerColumn
                        .frame(minWidth: 220, idealWidth: 300, maxWidth: 400)
                }

                TerminalTabs(model: terminalTabs)
                    .frame(minWidth: 420, idealWidth: 660)
                    .layoutPriority(2)

                if !zoom.isFocusMode {
                    ChangesView(model: gitModel)
                        .frame(minWidth: 320, idealWidth: 420, maxWidth: 540)
                        .layoutPriority(1)
                }
            }
            .atelierSplitViewChrome()

            statusBar
        }
        .background(AtelierTheme.editor)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            gitModel.refresh()
            guard fileWatcher == nil else { return }
            let watcher = FileWatcher(path: state.path) {
                gitModel.invalidate()
            }
            fileWatcher = watcher
            watcher.start()
        }
        .onDisappear {
            fileWatcher?.stop()
            fileWatcher = nil
            gitModel.stop()
        }
    }

    private var folderName: String {
        (state.path as NSString).lastPathComponent
    }

    private var workspaceURL: URL {
        URL(fileURLWithPath: state.path, isDirectory: true)
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
                if let next = OpenFolder.pick() {
                    store.setWorkspace(next)
                }
            } label: {
                Image(systemName: "folder.badge.gearshape")
            }
            .buttonStyle(AtelierLuminareIconButtonStyle())
            .help("Change folder")

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
            AtelierShortcuts.zoomWorkspaceWindow()
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
                    if let next = OpenFolder.pick() {
                        store.setWorkspace(next)
                    }
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .buttonStyle(AtelierLuminareIconButtonStyle())
                .help("Change folder")
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .environment(\.atelierZoomScale, zoom.sidebarScale)

            FileTreeView(rootURL: workspaceURL) { url in
                terminalTabs.openFile(url)
            }
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
