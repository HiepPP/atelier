import AppKit
import SwiftTerm

enum TerminalRenderingPolicy {
    static func usesMetal(displayScale: CGFloat) -> Bool {
        displayScale > 1
    }

    static func usesFontSmoothing(displayScale _: CGFloat) -> Bool {
        true
    }
}

/// Bounds for the read-only terminal scrollback snapshot exposed to the Gemma
/// sidecar. The snapshot never logs its content.
enum TerminalScrollbackPolicy {
    static let defaultLines = 200
    static let maximumLines = 400

    static func clampedLines(_ requested: Int) -> Int {
        min(max(1, requested), maximumLines)
    }
}

@MainActor
final class TerminalController {
    private let processService: TerminalProcessService
    private let terminal = AtelierTerminalNativeView(frame: .zero)
    private var isActive = false
    private var isClosed = false

    /// Fires when an OSC 133 `D` command-finished mark arrives with an exit
    /// code. Never fires when the shell emits no OSC 133 marks.
    var onCommandFinished: ((Int32) -> Void)?

    var isProcessRunning: Bool {
        !isClosed && terminal.process.running
    }

    func currentForegroundAgentName() -> String? {
        guard !isClosed else { return nil }
        return ForegroundProcessAgentReader.agentName(
            ptyFileDescriptor: terminal.process.childfd,
            shellPID: terminal.process.shellPid
        )
    }

    func requestFocus() {
        guard !isClosed else { return }
        terminal.requestFocusWhenAttached()
    }

    init(workspacePath: String, processService: TerminalProcessService = TerminalProcessService()) {
        self.processService = processService
        terminal.nativeBackgroundColor = AppKitThemeAdapter.terminalBackground
        terminal.nativeForegroundColor = AppKitThemeAdapter.terminalForeground
        terminal.font = AtelierTypography.codeFont(size: AtelierTypography.terminalSize)
        terminal.hideScrollIndicator()
        terminal.applyAtelierAppearance()
        processService.start(in: terminal, workspacePath: workspacePath)
        registerCommandFinishedHandler()
        AppLogger.terminal.info("Started terminal session")
    }

    /// Returns the last `lines` rows of the terminal buffer as plain text.
    /// Reads the SwiftTerm buffer on the main actor and trims trailing blank
    /// rows. The content is never logged.
    func scrollbackSnapshot(lines requested: Int) -> String {
        guard !isClosed else { return "" }
        let limit = TerminalScrollbackPolicy.clampedLines(requested)
        let engine = terminal.getTerminal()
        let cols = max(1, engine.cols)
        let text = engine.getText(
            start: Position(col: 0, row: 0),
            end: Position(col: cols, row: Int.max)
        )
        var rows = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        while let last = rows.last,
              last.trimmingCharacters(in: .whitespaces).isEmpty {
            rows.removeLast()
        }
        return rows.suffix(limit).joined(separator: "\n")
    }

    private func registerCommandFinishedHandler() {
        terminal.getTerminal().registerOscHandler(code: 133) { [weak self] payload in
            guard let exitCode = TerminalController.commandExitCode(from: payload) else { return }
            Task { @MainActor [weak self] in
                self?.onCommandFinished?(exitCode)
            }
        }
    }

    private nonisolated static func commandExitCode(from payload: ArraySlice<UInt8>) -> Int32? {
        guard let text = String(bytes: payload, encoding: .utf8) else { return nil }
        let fields = text.split(separator: ";", omittingEmptySubsequences: false)
        guard let marker = fields.first, marker == "D" else { return nil }
        guard fields.count > 1, let code = Int32(fields[1]) else { return 0 }
        return code
    }

    func attach(isActive: Bool) -> AtelierTerminalNativeView {
        setActive(isActive)
        return terminal
    }

    func setActive(_ isActive: Bool) {
        guard self.isActive != isActive else { return }
        self.isActive = isActive
        if isActive {
            requestFocus()
        } else {
            terminal.releaseFocusIfNeeded()
        }
    }

    func updateScale(_ scale: CGFloat, displayScale: CGFloat) {
        let targetSize = AtelierFontScaling.snapped(
            AtelierTypography.terminalSize * scale,
            displayScale: displayScale
        )
        let usesFontSmoothing = TerminalRenderingPolicy.usesFontSmoothing(
            displayScale: displayScale
        )
        let fontChanged = abs(terminal.font.pointSize - targetSize) > 0.01
        let smoothingChanged = terminal.fontSmoothing != usesFontSmoothing
        guard fontChanged || smoothingChanged else { return }
        terminal.fontSmoothing = usesFontSmoothing
        if fontChanged {
            terminal.font = AtelierTypography.codeFont(size: targetSize)
        }
        terminal.setNeedsDisplay(terminal.bounds)
        terminal.layoutSubtreeIfNeeded()
    }

    func paste(_ text: String) {
        guard !isClosed, !text.isEmpty else { return }
        terminal.pasteText(text)
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
}

final class AtelierTerminalNativeView: LocalProcessTerminalView {
    private var shouldFocusWhenAttached = false
    private var preciseScrollRemainder: CGFloat = 0
    private var scrollWheelMonitor: Any?

    func hideScrollIndicator() {
        for case let scroller as NSScroller in subviews {
            scroller.isHidden = true
        }
    }

    func requestFocusWhenAttached() {
        shouldFocusWhenAttached = true
        focusIfPossible()
    }

    func pasteText(_ text: String) {
        guard !text.isEmpty else { return }
        requestFocusWhenAttached()
        let terminal = getTerminal()
        if terminal.bracketedPasteMode {
            let bracketedPasteStart: [UInt8] = [0x1b, 0x5b, 0x32, 0x30, 0x30, 0x7e]
            send(data: bracketedPasteStart[...])
        }
        send(txt: text)
        if terminal.bracketedPasteMode {
            let bracketedPasteEnd: [UInt8] = [0x1b, 0x5b, 0x32, 0x30, 0x31, 0x7e]
            send(data: bracketedPasteEnd[...])
        }
    }

    func releaseFocusIfNeeded() {
        guard let window, window.firstResponder === self else { return }
        window.makeFirstResponder(nil)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installScrollWheelMonitor()
        updateRendererForDisplay()
        focusIfPossible()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateRendererForDisplay()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAtelierAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window, let scrollWheelMonitor {
            NSEvent.removeMonitor(scrollWheelMonitor)
            self.scrollWheelMonitor = nil
        }
        super.viewWillMove(toWindow: newWindow)
    }

    private func handlePreciseScroll(_ event: NSEvent) -> Bool {
        let terminal = getTerminal()
        let shiftBypassesMouseReporting = event.modifierFlags.contains(.shift)
            && !terminal.mouseShiftCapture
        let scrollsTerminalBuffer = !allowMouseReporting
            || terminal.mouseMode == .off
            || shiftBypassesMouseReporting

        guard event.hasPreciseScrollingDeltas, scrollsTerminalBuffer, canScroll else {
            preciseScrollRemainder = 0
            return false
        }

        if event.phase.contains(.began) || event.momentumPhase.contains(.began) {
            preciseScrollRemainder = 0
        }

        preciseScrollRemainder += event.scrollingDeltaY
        let lineHeight = max(1, font.ascender - font.descender + font.leading)
        let lines = Int(abs(preciseScrollRemainder) / lineHeight)
        if lines > 0 {
            if preciseScrollRemainder > 0 {
                scrollUp(lines: lines)
                preciseScrollRemainder -= CGFloat(lines) * lineHeight
            } else {
                scrollDown(lines: lines)
                preciseScrollRemainder += CGFloat(lines) * lineHeight
            }
        }

        if event.phase.contains(.ended) || event.phase.contains(.cancelled)
            || event.momentumPhase.contains(.ended)
            || event.momentumPhase.contains(.cancelled) {
            preciseScrollRemainder = 0
        }

        return true
    }

    private func installScrollWheelMonitor() {
        if let scrollWheelMonitor {
            NSEvent.removeMonitor(scrollWheelMonitor)
            self.scrollWheelMonitor = nil
        }
        guard let window else { return }
        scrollWheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) {
            [weak self, weak window] event in
            guard let self,
                  let window,
                  event.window === window,
                  self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else {
                return event
            }
            return self.handlePreciseScroll(event) ? nil : event
        }
    }

    private func updateRendererForDisplay() {
        guard let window else { return }
        let shouldUseMetal = TerminalRenderingPolicy.usesMetal(
            displayScale: window.backingScaleFactor
        )
        guard isUsingMetalRenderer != shouldUseMetal else { return }
        do {
            try setUseMetal(shouldUseMetal)
        } catch {
            AppLogger.terminal.warning(
                "Terminal renderer update failed: \(error.localizedDescription, privacy: .public)"
            )
        }
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

    func applyAtelierAppearance() {
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        nativeBackgroundColor = AppKitThemeAdapter.editor(usesDarkAppearance: isDark)
        nativeForegroundColor = AppKitThemeAdapter.terminalForeground(
            usesDarkAppearance: isDark
        )
        installColors(isDark ? TerminalPalette.dark : TerminalPalette.light)
        setNeedsDisplay(bounds)
    }
}

private enum TerminalPalette {
    static let light: [SwiftTerm.Color] = [
        color(0x4B, 0x49, 0x44), color(0xB8, 0x3A, 0x32),
        color(0x4F, 0x7B, 0x55), color(0x8A, 0x6C, 0x24),
        color(0x3C, 0x68, 0x96), color(0x86, 0x4F, 0x78),
        color(0x00, 0x7A, 0x91), color(0xC9, 0xC5, 0xBC),
        color(0x72, 0x6F, 0x68), color(0xD1, 0x53, 0x45),
        color(0x5F, 0x8F, 0x66), color(0xA0, 0x7E, 0x2D),
        color(0x4E, 0x7C, 0xB0), color(0x9B, 0x62, 0x8E),
        color(0x00, 0x8D, 0xA5), color(0xF1, 0xEE, 0xE7)
    ]

    static let dark: [SwiftTerm.Color] = [
        color(0x2C, 0x31, 0x2F), color(0xD9, 0x70, 0x67),
        color(0x7F, 0xBC, 0x89), color(0xD0, 0xA7, 0x5C),
        color(0x72, 0xA8, 0xD4), color(0xB8, 0x8A, 0xC5),
        color(0x65, 0xB9, 0xB2), color(0xD8, 0xDD, 0xDA),
        color(0x6E, 0x75, 0x72), color(0xEB, 0x8A, 0x82),
        color(0x98, 0xD0, 0xA0), color(0xE1, 0xBD, 0x75),
        color(0x8B, 0xBB, 0xE0), color(0xCA, 0xA0, 0xD4),
        color(0x7A, 0xCE, 0xC6), color(0xF0, 0xF3, 0xF1)
    ]

    private static func color(
        _ red: UInt16,
        _ green: UInt16,
        _ blue: UInt16
    ) -> SwiftTerm.Color {
        SwiftTerm.Color(red: red * 257, green: green * 257, blue: blue * 257)
    }
}
