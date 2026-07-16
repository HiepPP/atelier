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

private struct FileTab {
    let url: URL
    let content: FileContent
}

private enum CenterTabContent {
    case terminal(TerminalSession)
    case file(FileTab)
}

private final class CenterTab: Identifiable {
    let id: UUID
    let content: CenterTabContent

    init(id: UUID = UUID(), content: CenterTabContent) {
        self.id = id
        self.content = content
    }

    var title: String {
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
        let content = FileLoader.load(url: standardizedURL)

        if let index = tabs.firstIndex(where: { tab in
            guard case .file(let file) = tab.content else { return false }
            return file.url.standardizedFileURL == standardizedURL
        }) {
            let refreshed = CenterTab(
                id: tabs[index].id,
                content: .file(FileTab(url: standardizedURL, content: content))
            )
            tabs[index] = refreshed
            selectedID = refreshed.id
            return
        }

        let tab = CenterTab(content: .file(FileTab(url: standardizedURL, content: content)))
        tabs.append(tab)
        selectedID = tab.id
    }

    fileprivate func close(_ tab: CenterTab) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        if case .terminal(let session) = tab.content {
            session.close()
        }
        tabs.remove(at: index)
        if selectedID == tab.id {
            selectedID = tabs.indices.contains(index)
                ? tabs[index].id
                : tabs.last?.id
        }
    }
}

struct TerminalTabs: View {
    @ObservedObject var model: TerminalTabsModel
    @EnvironmentObject private var zoom: AtelierZoomModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                        }
                    }
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
                    FileViewer(content: file.content, fileURL: file.url)
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
