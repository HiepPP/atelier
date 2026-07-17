import AppKit
import Observation
import SwiftTerm

enum TerminalRenderingPolicy {
    static func usesMetal(displayScale: CGFloat) -> Bool {
        displayScale > 1
    }

    static func usesFontSmoothing(displayScale _: CGFloat) -> Bool {
        true
    }
}

@MainActor
@Observable
final class TerminalController {
    private let processService: TerminalProcessService
    private let terminal = AtelierTerminalNativeView(frame: .zero)
    private let mermaidMonitor: AgentTranscriptMermaidMonitor
    private let mermaidRenderer = MermaidImageRenderer()
    private var isClosed = false
    private var mermaidTranscriptTask: Task<Void, Never>?
    private var mermaidRenderTask: Task<Void, Never>?
    private var pendingMermaidDiagrams: [AgentMermaidDiagram] = []
    private var handledMermaidIDs: Set<String> = []
    private var mermaidImageIDs: [String: UInt32] = [:]
    private var nextMermaidImageID: UInt32 = 1

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
        mermaidMonitor = AgentTranscriptMermaidMonitor(workspacePath: workspacePath)
        terminal.nativeBackgroundColor = AppKitThemeAdapter.terminalBackground
        terminal.nativeForegroundColor = AppKitThemeAdapter.terminalForeground
        terminal.font = AtelierTypography.codeFont(size: AtelierTypography.terminalSize)
        terminal.installColors(Self.lightAnsiPalette)
        terminal.onOutputActivity = { [weak self] in
            self?.scheduleMermaidTranscriptScan()
        }
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
        mermaidTranscriptTask?.cancel()
        mermaidRenderTask?.cancel()
        processService.stop(terminal)
        AppLogger.terminal.info("Stopped terminal session")
    }

    isolated deinit {
        close()
    }

    private func scheduleMermaidTranscriptScan() {
        mermaidTranscriptTask?.cancel()
        mermaidTranscriptTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1_200))
            guard !Task.isCancelled, let self else { return }
            let diagrams = await mermaidMonitor.diagrams()
            guard !Task.isCancelled else { return }
            enqueueMermaidDiagrams(diagrams)
        }
    }

    private func enqueueMermaidDiagrams(_ diagrams: [AgentMermaidDiagram]) {
        if !terminal.hasInlineImages,
           mermaidRenderTask == nil,
           pendingMermaidDiagrams.isEmpty {
            handledMermaidIDs.subtract(diagrams.map(\.id))
        }
        for diagram in diagrams where handledMermaidIDs.insert(diagram.id).inserted {
            pendingMermaidDiagrams.append(diagram)
        }
        guard mermaidRenderTask == nil, !pendingMermaidDiagrams.isEmpty else { return }
        mermaidRenderTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !pendingMermaidDiagrams.isEmpty, !Task.isCancelled {
                let diagram = pendingMermaidDiagrams.removeFirst()
                let imageID = imageID(for: diagram)
                do {
                    let outputRevision = terminal.outputRevision
                    let width = MermaidRenderingPolicy.targetWidth(
                        containerWidth: terminal.bounds.width
                    )
                    let png = try await mermaidRenderer.render(
                        source: diagram.source,
                        width: width
                    )
                    guard !Task.isCancelled else { break }
                    guard terminal.outputRevision == outputRevision else { continue }
                    terminal.hideMermaidSources([diagram.source])
                    terminal.insertInlineImage(png, id: imageID, width: width)
                } catch {
                    AppLogger.terminal.warning(
                        "Inline Mermaid rendering failed: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
            mermaidRenderTask = nil
        }
    }

    private func imageID(for diagram: AgentMermaidDiagram) -> UInt32 {
        if let imageID = mermaidImageIDs[diagram.id] {
            return imageID
        }
        let imageID = nextMermaidImageID
        nextMermaidImageID &+= 1
        if nextMermaidImageID == 0 {
            nextMermaidImageID = 1
        }
        mermaidImageIDs[diagram.id] = imageID
        return imageID
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
    var onOutputActivity: (() -> Void)?
    private(set) var outputRevision: UInt64 = 0
    private var shouldFocusWhenAttached = false
    private var preciseScrollRemainder: CGFloat = 0
    private var scrollWheelMonitor: Any?

    func requestFocusWhenAttached() {
        shouldFocusWhenAttached = true
        focusIfPossible()
    }

    func insertInlineImage(_ png: Data, id: UInt32, width: CGFloat) {
        let payload = Array(png.base64EncodedString().utf8)
        let columns = MermaidRenderingPolicy.imageColumns(
            imageWidth: width,
            terminalWidth: bounds.width,
            terminalColumns: getTerminal().cols
        )
        feed(text: "\r\n")

        for offset in stride(from: 0, to: payload.count, by: 4_096) {
            let end = min(offset + 4_096, payload.count)
            let chunk = String(decoding: payload[offset..<end], as: UTF8.self)
            let hasMore = end < payload.count ? 1 : 0
            let control = offset == 0
                ? "a=T,f=100,t=d,i=\(id),p=\(id),q=2,c=\(columns),m=\(hasMore)"
                : "m=\(hasMore)"
            feed(text: "\u{1B}_G\(control);\(chunk)\u{1B}\\")
        }
        feed(text: "\r\n")
    }

    var hasInlineImages: Bool {
        getTerminal().buffer.hasAnyImages
    }

    func hideMermaidSources(_ sources: [String]) {
        guard !sources.isEmpty else { return }
        let terminal = getTerminal()
        var rows: [(line: BufferLine, text: String)] = []
        var row = terminal.buffer.totalLinesTrimmed

        while let line = terminal.getScrollInvariantLine(row: row) {
            rows.append((
                line,
                line.translateToString(
                    trimRight: true,
                    characterProvider: terminal.getCharacter(for:)
                )
            ))
            row += 1
        }

        let ranges = MermaidTerminalSourceLocator.ranges(
            in: rows.map(\.text),
            sources: sources
        )
        guard !ranges.isEmpty else { return }
        for range in ranges {
            for index in range {
                let line = rows[index].line
                for column in 0..<line.count {
                    let emptyCell = terminal.makeCharData(
                        attribute: line[column].attribute,
                        code: 0
                    )
                    line[column] = emptyCell
                }
            }
        }
        terminal.updateFullScreen()
        setNeedsDisplay(bounds)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installScrollWheelMonitor()
        updateRendererForDisplay()
        focusIfPossible()
    }

    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)
        outputRevision &+= 1
        onOutputActivity?()
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
