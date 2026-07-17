import AppKit
import SwiftTerm

enum TerminalRenderingPolicy {
    static func usesMetal(displayScale: CGFloat) -> Bool {
        displayScale > 1
    }

    static func usesFontSmoothing(displayScale: CGFloat) -> Bool {
        displayScale > 1
    }
}

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
        terminal.font = AtelierTypography.codeFont(size: AtelierTypography.terminalSize)
        terminal.installColors(Self.lightAnsiPalette)
        processService.start(in: terminal, workspacePath: workspacePath)
        AppLogger.terminal.info("Started terminal session")
    }

    func attach() -> AtelierTerminalNativeView {
        terminal.requestFocusWhenAttached()
        return terminal
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
    private var preciseScrollRemainder: CGFloat = 0
    private var scrollWheelMonitor: Any?

    func requestFocusWhenAttached() {
        shouldFocusWhenAttached = true
        focusIfPossible()
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
}
