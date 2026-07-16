import AppKit
import SwiftTerm

@MainActor
final class TerminalController {
    private let processService: TerminalProcessService
    private let terminal = AtelierTerminalNativeView(frame: .zero)
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

    init(workspacePath: String, processService: TerminalProcessService = TerminalProcessService()) {
        self.processService = processService
        terminal.nativeBackgroundColor = AppKitThemeAdapter.terminalBackground
        terminal.nativeForegroundColor = AppKitThemeAdapter.terminalForeground
        terminal.font = .monospacedSystemFont(ofSize: 13.5, weight: .regular)
        terminal.installColors(Self.lightAnsiPalette)
        processService.start(in: terminal, workspacePath: workspacePath)
        AppLogger.terminal.info("Started terminal session")
    }

    func attach() -> AtelierTerminalNativeView {
        terminal.requestFocusWhenAttached()
        return terminal
    }

    func updateScale(_ scale: CGFloat) {
        let targetSize = 13.5 * scale
        guard abs(terminal.font.pointSize - targetSize) > 0.01 else { return }
        terminal.font = .monospacedSystemFont(ofSize: targetSize, weight: .regular)
        terminal.setNeedsDisplay(terminal.bounds)
        terminal.layoutSubtreeIfNeeded()
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        processService.stop(terminal)
        AppLogger.terminal.info("Stopped terminal session")
    }

    isolated deinit {
        close()
    }

    private static func terminalColor(
        _ red: UInt16,
        _ green: UInt16,
        _ blue: UInt16
    ) -> SwiftTerm.Color {
        SwiftTerm.Color(red: red * 257, green: green * 257, blue: blue * 257)
    }
}

final class AtelierTerminalNativeView: LocalProcessTerminalView {
    private var shouldFocusWhenAttached = false

    func requestFocusWhenAttached() {
        shouldFocusWhenAttached = true
        focusIfPossible()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        focusIfPossible()
    }

    private func focusIfPossible() {
        guard shouldFocusWhenAttached, let window else { return }
        shouldFocusWhenAttached = false
        Task { @MainActor [weak self, weak window] in
            await Task.yield()
            guard let self, let window else { return }
            window.makeFirstResponder(self)
        }
    }
}
