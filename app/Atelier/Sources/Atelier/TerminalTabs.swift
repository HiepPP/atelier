import AppKit
import SwiftUI
import SwiftTerm

final class TerminalSession: Identifiable {
    let id = UUID()
    let title: String
    let terminal = LocalProcessTerminalView(frame: .zero)
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

final class TerminalTabsModel: ObservableObject {
    @Published private(set) var sessions: [TerminalSession] = []
    @Published var selectedID: UUID?

    private let workspacePath: String
    private var nextNumber = 1

    init(workspacePath: String) {
        self.workspacePath = workspacePath
        add()
    }

    var selectedSession: TerminalSession? {
        sessions.first { $0.id == selectedID }
    }

    func add() {
        let session = TerminalSession(number: nextNumber, workspacePath: workspacePath)
        nextNumber += 1
        sessions.append(session)
        selectedID = session.id
    }

    func close(_ session: TerminalSession) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        session.close()
        sessions.remove(at: index)
        if selectedID == session.id {
            selectedID = sessions.indices.contains(index)
                ? sessions[index].id
                : sessions.last?.id
        }
    }
}

struct TerminalTabs: View {
    @ObservedObject var model: TerminalTabsModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(model.sessions) { session in
                            HStack(spacing: 7) {
                                Button {
                                    model.close(session)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8, weight: .medium))
                                }
                                .buttonStyle(.borderless)
                                .help("Close terminal")

                                Button {
                                    withAnimation(
                                        reduceMotion
                                            ? nil
                                            : .spring(response: 0.28, dampingFraction: 0.84)
                                    ) {
                                        model.selectedID = session.id
                                    }
                                } label: {
                                    HStack(spacing: 7) {
                                        Image(systemName: "terminal")
                                            .font(.system(size: 10, weight: .regular))
                                        Text(session.title)
                                            .font(
                                                .system(
                                                    size: 11.5,
                                                    weight: .medium
                                                )
                                            )
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityValue(
                                    model.selectedID == session.id ? "Selected" : "Not selected"
                                )
                            }
                            .foregroundStyle(
                                model.selectedID == session.id ? Color.primary : Color.secondary
                            )
                            .padding(.horizontal, 12)
                            .frame(height: 42)
                            .background(
                                model.selectedID == session.id
                                    ? AtelierTheme.editor
                                    : AtelierTheme.tabInactive
                            )
                            .overlay(alignment: .top) {
                                if model.selectedID == session.id {
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
                            .contentShape(Rectangle())
                        }
                    }
                }
                .atelierScrollChrome(backgroundColor: AtelierNativePalette.chrome)

                Button {
                    model.add()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(AtelierIconButtonStyle())
                .help("New terminal")

                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .medium))
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

            if let session = model.selectedSession {
                TerminalView(terminal: session.terminal)
                    .id(session.id)
                    .background(AtelierTheme.editor)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "terminal")
                        .font(.system(size: 42, weight: .ultraLight))
                        .foregroundStyle(AtelierTheme.accent)
                    Text("No Terminal")
                        .font(.system(size: 22, weight: .semibold))
                        .tracking(-0.5)
                    Text("Add a terminal tab to start a shell.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
