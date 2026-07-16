import AppKit
import SwiftUI
import SwiftTerm

final class TerminalSession: Identifiable {
    let id = UUID()
    let title: String
    let terminal = AtelierTerminalNativeView(frame: .zero)
    private var isClosed = false

    private static let lightAnsiPalette: [SwiftTerm.Color] = [
        terminalColor(0x4b, 0x49, 0x44), terminalColor(0xb8, 0x3a, 0x32),
        terminalColor(0x4f, 0x7b, 0x55), terminalColor(0x8a, 0x6c, 0x24),
        terminalColor(0x3c, 0x68, 0x96), terminalColor(0x86, 0x4f, 0x78),
        terminalColor(0x00, 0x7a, 0x91), terminalColor(0xc9, 0xc5, 0xbc),
        terminalColor(0x72, 0x6f, 0x68), terminalColor(0xd1, 0x53, 0x45),
        terminalColor(0x5f, 0x8f, 0x66), terminalColor(0xa0, 0x7e, 0x2d),
        terminalColor(0x4e, 0x7c, 0xb0), terminalColor(0x9b, 0x62, 0x8e),
        terminalColor(0x00, 0x8d, 0xa5), terminalColor(0xf1, 0xee, 0xe7)
    ]

    init(number: Int, workspacePath: String) {
        title = "Terminal \(number)"
        terminal.nativeBackgroundColor = AtelierNativePalette.terminalBackground
        terminal.nativeForegroundColor = AtelierNativePalette.terminalForeground
        terminal.font = .monospacedSystemFont(ofSize: 13.5, weight: .regular)
        terminal.installColors(Self.lightAnsiPalette)
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let shellName = (shell as NSString).lastPathComponent
        var environment = ProcessInfo.processInfo.environment.map { "\($0.key)=\($0.value)" }
        environment.removeAll { $0.hasPrefix("TERM=") }
        environment.append("TERM=xterm-256color")
        terminal.startProcess(
            executable: shell,
            args: [],
            environment: environment,
            execName: "-\(shellName)",
            currentDirectory: workspacePath
        )
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        terminal.terminate()
    }

    deinit {
        close()
    }

    private static func terminalColor(_ red: UInt16, _ green: UInt16, _ blue: UInt16) -> SwiftTerm.Color {
        SwiftTerm.Color(red: red * 257, green: green * 257, blue: blue * 257)
    }
}

private final class FileTab: ObservableObject {
    let url: URL
    @Published private(set) var content: FileContent = .loading
    private var loadTask: Task<Void, Never>?

    init(url: URL) {
        self.url = url
        reload()
    }

    func reload() {
        loadTask?.cancel()
        content = .loading
        let url = url
        loadTask = Task { @MainActor [weak self] in
            let content = await FileLoader.loadAsync(url: url)
            guard !Task.isCancelled else { return }
            self?.content = content
        }
    }

    func close() {
        loadTask?.cancel()
        loadTask = nil
    }

    deinit {
        loadTask?.cancel()
    }
}

private enum CenterTabContent {
    case terminal(TerminalSession)
    case file(FileTab)
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
            return file.url.lastPathComponent
        }
    }

    var systemImage: String {
        switch content {
        case .terminal:
            return "terminal"
        case .file:
            return "doc.text"
        }
    }

    var closeHelp: String {
        switch content {
        case .terminal:
            return "Close terminal"
        case .file:
            return "Close file"
        }
    }
}

final class TerminalTabsModel: ObservableObject {
    @Published private var tabs: [CenterTab] = []
    @Published var selectedID: UUID?

    private let workspacePath: String
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

    var terminalCount: Int {
        tabs.reduce(into: 0) { count, tab in
            if case .terminal = tab.content {
                count += 1
            }
        }
    }

    func add() {
        let session = TerminalSession(number: nextNumber, workspacePath: workspacePath)
        let tab = CenterTab(content: .terminal(session))
        nextNumber += 1
        tabs.append(tab)
        selectedID = tab.id
    }

    func openFile(_ url: URL) {
        let standardizedURL = url.standardizedFileURL

        if let tab = tabs.first(where: { tab in
            guard case .file(let file) = tab.content else { return false }
            return file.url.standardizedFileURL == standardizedURL
        }) {
            guard case .file(let file) = tab.content else { return }
            file.reload()
            selectedID = tab.id
            return
        }

        let tab = CenterTab(content: .file(FileTab(url: standardizedURL)))
        tabs.append(tab)
        selectedID = tab.id
    }

    fileprivate func close(_ tab: CenterTab) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        switch tab.content {
        case .terminal(let session):
            session.close()
        case .file(let file):
            file.close()
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
}

private struct RenameActiveTabKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var renameActiveTab: (() -> Void)? {
        get { self[RenameActiveTabKey.self] }
        set { self[RenameActiveTabKey.self] = newValue }
    }
}

struct AtelierTabCommands: Commands {
    @FocusedValue(\.renameActiveTab) private var renameActiveTab

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Rename Tab...") {
                renameActiveTab?()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(renameActiveTab == nil)
        }
    }
}

struct TerminalTabs: View {
    @ObservedObject var model: TerminalTabsModel
    @EnvironmentObject private var zoom: AtelierZoomModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var renameTargetID: UUID?
    @State private var tabFrames: [UUID: CGRect] = [:]
    @State private var draggedTabID: UUID?
    @State private var lastReorderTargetID: UUID?

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
                                        model.selectedID = tab.id
                                    }
                                } label: {
                                    HStack(spacing: 7) {
                                        Color.clear
                                            .frame(width: 9, height: 9)
                                        Image(systemName: tab.systemImage)
                                            .atelierFont(size: 10)
                                        Text(tab.title)
                                            .atelierFont(size: 11.5, weight: .medium)
                                            .lineLimit(1)
                                    }
                                    .padding(.horizontal, 12)
                                    .frame(height: 42)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityValue(
                                    model.selectedID == tab.id ? "Selected" : "Not selected"
                                )

                                Button {
                                    model.close(tab)
                                } label: {
                                    Image(systemName: "xmark")
                                        .atelierFont(size: 8, weight: .medium)
                                        .frame(width: 28, height: 42)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.borderless)
                                .help(tab.closeHelp)
                            }
                            .foregroundStyle(
                                model.selectedID == tab.id ? Color.primary : Color.secondary
                            )
                            .background(
                                model.selectedID == tab.id
                                    ? AtelierTheme.editor
                                    : AtelierTheme.tabInactive
                            )
                            .overlay(alignment: .top) {
                                if model.selectedID == tab.id {
                                    Rectangle()
                                        .fill(AtelierTheme.gitOrange)
                                        .frame(height: 1.5)
                                }
                            }
                            .overlay(alignment: .trailing) {
                                Rectangle()
                                    .fill(AtelierTheme.border)
                                    .frame(width: 0.5)
                            }
                            .overlay {
                                PointingHandCursorRegion()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active:
                                    NSCursor.pointingHand.set()
                                case .ended:
                                    NSCursor.arrow.set()
                                }
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
                .atelierScrollChrome(backgroundColor: AtelierNativePalette.chrome)

                Button {
                    model.add()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(AtelierLuminareIconButtonStyle())
                .atelierNewTerminalEffect(sessionCount: model.terminalCount)
                .help("New terminal")

                Image(systemName: "ellipsis")
                    .atelierFont(size: 11, weight: .medium)
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 40)
                    .accessibilityHidden(true)
            }
            .padding(.trailing, 5)
            .frame(height: 42)
            .background(AtelierTheme.chrome)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(AtelierTheme.border)
                    .frame(height: 0.5)
            }

            if let tab = model.selectedTab {
                switch tab.content {
                case .terminal(let session):
                    TerminalView(
                        terminal: session.terminal,
                        scale: zoom.contentScale
                    )
                        .id(tab.id)
                        .background(AtelierTheme.editor)
                case .file(let file):
                    FileTabView(file: file)
                        .id(tab.id)
                        .background(AtelierTheme.editor)
                        .environment(\.atelierZoomScale, zoom.contentScale)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.stack")
                        .atelierFont(size: 42, weight: .ultraLight)
                        .foregroundStyle(AtelierTheme.accent)
                    Text("No Open Tabs")
                        .atelierFont(size: 22, weight: .semibold)
                        .tracking(-0.5)
                    Text("Open a file or add a terminal tab.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .focusedSceneValue(\.renameActiveTab) {
            guard let selectedID = model.selectedID else { return }
            beginRename(selectedID)
        }
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

    private var renameTargetTitle: String {
        guard let renameTargetID,
              let tab = model.visibleTabs.first(where: { $0.id == renameTargetID }) else {
            return "Tab name"
        }
        return tab.title
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

private struct FileTabView: View {
    @ObservedObject var file: FileTab

    var body: some View {
        FileViewer(content: file.content, fileURL: file.url)
    }
}

private struct TabRenameSheet: View {
    let currentTitle: String
    let onRename: (String) -> Void
    let onCancel: () -> Void

    @State private var title = ""
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rename Tab")
                .atelierFont(size: 15, weight: .semibold)

            TextField("Tab name", text: $title, prompt: Text(currentTitle))
                .textFieldStyle(.roundedBorder)
                .focused($isTitleFocused)
                .onSubmit(submit)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .atelierPointerCursor()
                Button("Rename", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(cleanTitle.isEmpty)
                    .atelierPointerCursor()
            }
        }
        .padding(20)
        .frame(width: 340)
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
