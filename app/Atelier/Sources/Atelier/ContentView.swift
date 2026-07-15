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
        .frame(minWidth: 1_000, minHeight: 600)
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
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(2.4)
                        .foregroundStyle(AtelierTheme.accent)

                    Text("Chưa mở workspace")
                        .font(.system(size: 38, weight: .semibold, design: .default))
                        .tracking(-1.4)

                    Text("Chọn một folder để xem changes, đọc file và chạy terminal.")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 360, alignment: .leading)

                    Button {
                        if let state = OpenFolder.pick() {
                            store.setWorkspace(state)
                        }
                    } label: {
                        Label("Mở Folder", systemImage: "arrow.up.right")
                    }
                    .buttonStyle(AtelierPrimaryButtonStyle())
                    .keyboardShortcut("o", modifiers: .command)
                }

                Spacer(minLength: 0)

                Image(systemName: "folder")
                    .font(.system(size: 116, weight: .ultraLight))
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
    @State private var selectedFile: URL?
    @State private var fileContent: FileContent = .text("Select a file to preview.")
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

            HStack(spacing: 0) {
                HSplitView {
                    explorerColumn
                        .frame(minWidth: 220, idealWidth: 300, maxWidth: 400)

                    TerminalTabs(model: terminalTabs)
                        .frame(minWidth: 420, idealWidth: 660)
                        .layoutPriority(2)

                    ChangesView(model: gitModel)
                        .frame(minWidth: 320, idealWidth: 420, maxWidth: 540)
                        .layoutPriority(1)
                }
                .atelierSplitViewChrome()
            }

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
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(folderName)
                    .font(.system(size: 11.5, weight: .medium))
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

            Button {
                if let next = OpenFolder.pick() {
                    store.setWorkspace(next)
                }
            } label: {
                Image(systemName: "folder.badge.gearshape")
            }
            .buttonStyle(AtelierIconButtonStyle())
            .help("Change folder")

            Image(systemName: "gearshape")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: 40)
        .background(AtelierTheme.chrome)
    }

    private var explorerColumn: some View {
        VStack(spacing: 0) {
            explorerActivityBar

            HStack {
                Text(folderName.uppercased())
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    if let next = OpenFolder.pick() {
                        store.setWorkspace(next)
                    }
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .buttonStyle(AtelierIconButtonStyle())
                .help("Change folder")
            }
            .padding(.horizontal, 12)
            .frame(height: 36)

            FileTreeView(rootURL: workspaceURL) { url in
                selectedFile = url
                fileContent = FileLoader.load(url: url)
            }

            if selectedFile != nil {
                Divider()

                HStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .foregroundStyle(AtelierTheme.accent)
                    Text(selectedFile?.path ?? "No file selected")
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(AtelierTheme.chrome)

                FileViewer(content: fileContent)
                    .frame(minHeight: 150, idealHeight: 230)
            }
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
                    .font(.system(size: 13, weight: .regular))
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
            Text("Explorer")
            Text("Terminal")
            Text("Git")
        }
        .font(.system(size: 10.5, weight: .medium))
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
