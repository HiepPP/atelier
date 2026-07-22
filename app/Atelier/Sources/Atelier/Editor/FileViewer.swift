import AppKit
import HighlightSwift
import SwiftUI

@MainActor
private final class RuntimeDiagnosticScrollView: NSScrollView {
    weak var runtimeDiagnosticsController: FileViewer.NativeEditorController?

    override func scrollWheel(with event: NSEvent) {
        let before = contentView.bounds.origin.y
        super.scrollWheel(with: event)
        runtimeDiagnosticsController?.recordScrollInput(
            beforeY: before,
            afterY: contentView.bounds.origin.y,
            deltaY: event.scrollingDeltaY
        )
    }
}

enum FileHighlightPolicy {
    static let maximumHighlightedBytes = 200_000

    static func usesSyntaxHighlighting(byteCount: Int) -> Bool {
        byteCount <= maximumHighlightedBytes
    }
}

enum FileLayoutPolicy {
    // TextKit 1 lays out every previewable text file eagerly, so the scroller
    // reflects the true document height and lines never render lazily. The cap
    // matches the loader limit; anything larger is surfaced as `.tooLarge`.
    static let maximumFullLayoutBytes = FileLoader.defaultLimit

    static func usesFullLayout(byteCount: Int) -> Bool {
        byteCount <= maximumFullLayoutBytes
    }
}

struct FileViewer: NSViewRepresentable {
    @Environment(\.atelierZoomScale) private var scale
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme

    let content: FileContent
    let fileURL: URL?
    let language: HighlightLanguage?
    let isActive: Bool
    let isWordWrapEnabled: Bool
    let surfaceOwner: EditorSession?
    let onEdit: () -> Void

    init(
        content: FileContent,
        fileURL: URL? = nil,
        language: HighlightLanguage? = nil,
        isActive: Bool = true,
        isWordWrapEnabled: Bool = true,
        surfaceOwner: EditorSession? = nil,
        onEdit: @escaping () -> Void = {}
    ) {
        self.content = content
        self.fileURL = fileURL
        self.language = language ?? fileURL.flatMap(FileViewerLanguage.language(for:))
        self.isActive = isActive
        self.isWordWrapEnabled = isWordWrapEnabled
        self.surfaceOwner = surfaceOwner
        self.onEdit = onEdit
    }

    func makeCoordinator() -> NativeEditorController {
        NativeEditorController()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let mountState = RuntimeSignposts.signposter.beginInterval("EditorMount")
        let scrollView = RuntimeDiagnosticScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = !isWordWrapEnabled
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = AppKitThemeAdapter.code
        scrollView.scrollerStyle = .overlay
        scrollView.clipsToBounds = true
        scrollView.contentView.clipsToBounds = true

        let contentSize = scrollView.contentSize
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        layoutManager.allowsNonContiguousLayout = true
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(
            containerSize: NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        )
        textContainer.widthTracksTextView = true
        textContainer.lineFragmentPadding = AtelierMetrics.spaceM
        layoutManager.addTextContainer(textContainer)

        let textView = NSTextView(
            frame: NSRect(origin: .zero, size: contentSize),
            textContainer: textContainer
        )
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = !isWordWrapEnabled
        textView.autoresizingMask = isWordWrapEnabled ? [.width] : []
        textView.textContainerInset = NSSize(width: 0, height: AtelierMetrics.spaceM)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFontPanel = false
        textView.usesRuler = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.allowsUndo = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.drawsBackground = true
        textView.backgroundColor = AppKitThemeAdapter.code
        textView.insertionPointColor = AppKitThemeAdapter.accent
        textView.selectedTextAttributes = [
            .backgroundColor: AppKitThemeAdapter.selection
        ]

        scrollView.documentView = textView
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        scrollView.verticalRulerView = FileLineNumberRulerView(
            scrollView: scrollView,
            textView: textView
        )

        context.coordinator.attach(scrollView: scrollView, textView: textView)
        scrollView.runtimeDiagnosticsController = context.coordinator
        RuntimeSignposts.signposter.endInterval("EditorMount", mountState)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let usesDarkAppearance = colorScheme == .dark
        if context.coordinator.appliedBackgroundIsDark != usesDarkAppearance {
            context.coordinator.appliedBackgroundIsDark = usesDarkAppearance
            let background = AppKitThemeAdapter.editor(usesDarkAppearance: usesDarkAppearance)
            scrollView.backgroundColor = background
            if let textView = scrollView.documentView as? NSTextView {
                textView.backgroundColor = background
            }
            (scrollView.verticalRulerView as? FileLineNumberRulerView)?.backgroundColor = background
        }
        context.coordinator.update(
            content: content,
            fileURL: fileURL,
            language: language,
            scale: scale,
            displayScale: displayScale,
            usesDarkAppearance: usesDarkAppearance,
            isActive: isActive,
            isWordWrapEnabled: isWordWrapEnabled,
            surfaceOwner: surfaceOwner,
            onEdit: onEdit
        )
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: NSScrollView,
        context: Context
    ) -> CGSize? {
        CGSize(
            width: proposal.width ?? nsView.frame.width,
            height: proposal.height ?? nsView.frame.height
        )
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: NativeEditorController) {
        coordinator.stop()
    }

    @MainActor
    final class NativeEditorController: NSObject, NSTextViewDelegate, RuntimeDiagnosableEditorSurface {
        private static let highlightService = SyntaxHighlightService()
        private static let saveDelay: UInt64 = 350_000_000
        private static let highlightDelay: UInt64 = 450_000_000

        private weak var scrollView: NSScrollView?
        private weak var textView: NSTextView?
        private var renderedContent: FileContent?
        private var fileURL: URL?
        private var language: HighlightLanguage?
        private var renderedLanguage: String?
        private var renderedScale: CGFloat = 0
        private var renderedDisplayScale: CGFloat = 0
        private var usesDarkAppearance = false
        private var isActive = false
        private var renderedWordWrapEnabled: Bool?
        private var highlightGeneration = 0
        private var highlightTask: Task<Void, Never>?
        private var saveGeneration = 0
        private var saveTask: Task<Void, Never>?
        private var isApplyingText = false
        let runtimeDiagnosticID = UUID().uuidString
        private var runtimeObservationTokens: [NSObjectProtocol] = []
        private var runtimeWindowStartedAt = 0.0
        private var runtimeScrollInputs = 0
        private var runtimeBoundsChanges = 0
        private var runtimeEligibleNoMovementInputs = 0
        private var runtimeDocumentHeightChanges = 0
        private var runtimeCompletedScrollInputs = 0
        private var runtimeCompletedBoundsChanges = 0
        private var runtimeCompletedEligibleNoMovementInputs = 0
        private var runtimeCompletedDocumentHeightChanges = 0
        private var runtimeCompletedWindowAt = 0.0
        private var runtimeLastDocumentHeight = 0.0
        private var runtimeLastViewportWidth = 0.0
        private var runtimeLastBoundsOriginY = 0.0
        private var runtimeLayoutGraceUntil = 0.0
        private var runtimeHighlightState = "idle"
        private var runtimeHighlightStartedAt = 0.0
        private var runtimeHighlightDurationMs = 0.0
        private var runtimeHighlightCancellationCount = 0
        private var runtimeTextApplyDurationMs = 0.0
        private var runtimeContentBytes = 0
        private var runtimeLineCount = 0
        // Mirror of the current document text, kept in sync on content set and on
        // edit. Selection changes read this instead of rematerializing the whole
        // document string on every cursor move.
        private var cachedText = ""
        private weak var surfaceOwner: EditorSession?
        private var onEdit: () -> Void = {}
        private(set) var document: EditorDocument?
        // Tracks the applied background so updateNSView skips redundant
        // AppKit writes on unrelated SwiftUI updates.
        var appliedBackgroundIsDark: Bool?

        override init() {
            runtimeWindowStartedAt = Self.runtimeNow()
            super.init()
            RuntimeDiagnosticsService.shared.registerEditorController(id: runtimeDiagnosticID)
        }

        func attach(scrollView: NSScrollView, textView: NSTextView) {
            self.scrollView = scrollView
            self.textView = textView
            textView.delegate = self
            scrollView.contentView.postsBoundsChangedNotifications = true
            textView.postsFrameChangedNotifications = true
            runtimeLastDocumentHeight = textView.frame.height
            runtimeLastViewportWidth = scrollView.contentView.bounds.width
            runtimeLastBoundsOriginY = scrollView.contentView.bounds.origin.y
            runtimeObservationTokens = [
                NotificationCenter.default.addObserver(
                    forName: NSView.boundsDidChangeNotification,
                    object: scrollView.contentView,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.recordBoundsChange() }
                },
                NotificationCenter.default.addObserver(
                    forName: NSView.frameDidChangeNotification,
                    object: textView,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.recordDocumentHeightChange() }
                }
            ]
            RuntimeDiagnosticsService.shared.record(
                category: "editor",
                name: "nativeEditorMounted",
                correlationID: runtimeDiagnosticID
            )
        }

        @MainActor
        func update(
            content: FileContent,
            fileURL: URL?,
            language: HighlightLanguage?,
            scale: CGFloat,
            displayScale: CGFloat,
            usesDarkAppearance: Bool,
            isActive: Bool,
            isWordWrapEnabled: Bool,
            surfaceOwner: EditorSession?,
            onEdit: @escaping () -> Void
        ) {
            let contentChanged = renderedContent != content
                || renderedLanguage != language?.rawValue
                || self.usesDarkAppearance != usesDarkAppearance
            let scaleChanged = renderedScale != scale || renderedDisplayScale != displayScale
            let wordWrapChanged = renderedWordWrapEnabled != isWordWrapEnabled
            self.fileURL = fileURL
            if let fileURL {
                if document?.url != fileURL {
                    open(EditorDocument(url: fileURL))
                }
            } else {
                document = nil
            }
            self.language = language
            renderedScale = scale
            renderedDisplayScale = displayScale
            self.usesDarkAppearance = usesDarkAppearance
            updateActiveState(isActive)
            renderedWordWrapEnabled = isWordWrapEnabled
            if self.surfaceOwner !== surfaceOwner {
                self.surfaceOwner?.detach(surface: self)
                self.surfaceOwner = surfaceOwner
                surfaceOwner?.attach(surface: self)
            }
            self.onEdit = onEdit
            textView?.isEditable = isActive && fileURL != nil && content.isEditableText
            textView?.allowsUndo = textView?.isEditable == true

            if wordWrapChanged {
                beginRuntimeLayoutGrace()
                RuntimeDiagnosticsService.shared.record(
                    category: "editor",
                    name: "wordWrapLayoutChanged",
                    metadata: ["enabled": .boolean(isWordWrapEnabled)],
                    correlationID: runtimeDiagnosticID
                )
                applyWordWrap(isEnabled: isWordWrapEnabled)
            }
            if scaleChanged {
                beginRuntimeLayoutGrace()
                RuntimeDiagnosticsService.shared.record(
                    category: "editor",
                    name: "fontLayoutChanged",
                    correlationID: runtimeDiagnosticID
                )
                applyFont()
            }
            if contentChanged {
                beginRuntimeLayoutGrace()
                renderedContent = content
                renderedLanguage = language?.rawValue
                render(content: content, language: language)
            }
        }

        private func updateActiveState(_ isActive: Bool) {
            guard self.isActive != isActive else { return }
            self.isActive = isActive
            guard !isActive,
                  let textView,
                  let scrollView,
                  let window = textView.window,
                  let responder = window.firstResponder else { return }
            let responderView = responder as? NSView
            guard responder === textView || responderView?.isDescendant(of: scrollView) == true else {
                return
            }
            window.makeFirstResponder(nil)
        }

        @MainActor
        func stop() {
            highlightGeneration += 1
            highlightTask?.cancel()
            highlightTask = nil
            saveGeneration += 1
            saveTask?.cancel()
            saveTask = nil
            for token in runtimeObservationTokens {
                NotificationCenter.default.removeObserver(token)
            }
            runtimeObservationTokens.removeAll(keepingCapacity: false)
            (scrollView as? RuntimeDiagnosticScrollView)?.runtimeDiagnosticsController = nil
            textView?.delegate = nil
            surfaceOwner?.detach(surface: self)
            surfaceOwner = nil
            textView = nil
            scrollView = nil
            document = nil
            onEdit = {}
            RuntimeDiagnosticsService.shared.record(
                category: "editor",
                name: "nativeEditorStopped",
                correlationID: runtimeDiagnosticID
            )
        }

        isolated deinit {
            RuntimeDiagnosticsService.shared.unregisterEditorController(id: runtimeDiagnosticID)
        }

        func open(_ document: EditorDocument) {
            self.document = document
            fileURL = document.url
        }

        func save() async throws {
            guard let text = textView?.string, let fileURL else { return }
            try await FileSaver.saveAsync(text: text, url: fileURL)
        }

        func reveal(line: Int, column: Int) {
            guard line > 0, column > 0, let textView else { return }
            let text = cachedText
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            guard line <= lines.count else { return }
            let prefixLength = lines.prefix(line - 1).reduce(0) { $0 + $1.utf16.count + 1 }
            let location = min(prefixLength + column - 1, (text as NSString).length)
            let range = NSRange(location: location, length: 0)
            textView.setSelectedRange(range)
            textView.scrollRangeToVisible(range)
        }

        func focus() {
            guard let textView, let window = textView.window else { return }
            window.makeFirstResponder(textView)
        }

        func performFindAction(_ action: EditorFindAction) {
            guard let textView else { return }
            let finderAction: NSTextFinder.Action
            switch action {
            case .showFindInterface:
                finderAction = .showFindInterface
            case .showReplaceInterface:
                finderAction = .showReplaceInterface
            case .nextMatch:
                finderAction = .nextMatch
            case .previousMatch:
                finderAction = .previousMatch
            case .setSearchString:
                finderAction = .setSearchString
            }
            focus()
            let sender = NSMenuItem()
            sender.tag = finderAction.rawValue
            textView.performTextFinderAction(sender)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView,
                  notification.object as? NSTextView === textView else { return }
            updateSelectionState(textView)
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingText,
                  let textView = notification.object as? NSTextView,
                  let fileURL else { return }
            let text = textView.string
            cachedText = text
            updateRuntimeContentMetrics(text)
            beginRuntimeLayoutGrace()
            lineNumberView?.updateLineStarts(for: text)
            onEdit()
            scheduleSave(text: text, url: fileURL)
            scheduleHighlight(text: text, language: language, delayed: true)
        }

        @MainActor
        private func render(content: FileContent, language: HighlightLanguage?) {
            highlightGeneration += 1
            highlightTask?.cancel()
            highlightTask = nil
            beginRuntimeLayoutGrace()

            let isText: Bool
            let foregroundColor: NSColor
            switch content {
            case .text:
                isText = true
                foregroundColor = AppKitThemeAdapter.foreground
            case .loading, .image, .binary, .tooLarge, .error:
                isText = false
                foregroundColor = AppKitThemeAdapter.secondary
            }

            apply(
                NSAttributedString(
                    string: content.displayText,
                    attributes: baseAttributes(foregroundColor: foregroundColor)
                )
            )

            guard isText,
                  case .text(let text) = content,
                  FileHighlightPolicy.usesSyntaxHighlighting(byteCount: text.utf8.count) else {
                return
            }

            scheduleHighlight(text: text, language: language, delayed: false)
        }

        @MainActor
        private func scheduleSave(text: String, url: URL) {
            saveGeneration += 1
            let expectedGeneration = saveGeneration
            saveTask?.cancel()
            saveTask = Task { [weak self] in
                do {
                    try await Task.sleep(nanoseconds: Self.saveDelay)
                    guard !Task.isCancelled else { return }
                    guard self?.textView?.string == text, self?.fileURL == url else { return }
                    try await self?.save()
                    guard !Task.isCancelled,
                          self?.saveGeneration == expectedGeneration else { return }
                    self?.textView?.toolTip = nil
                } catch {
                    guard !(error is CancellationError),
                          self?.saveGeneration == expectedGeneration else { return }
                    self?.textView?.toolTip = "Auto-save failed: \(error.localizedDescription)"
                    AppLogger.editor.error(
                        "Auto-save failed: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
        }

        @MainActor
        private func scheduleHighlight(
            text: String,
            language: HighlightLanguage?,
            delayed: Bool
        ) {
            highlightGeneration += 1
            let expectedGeneration = highlightGeneration
            if highlightTask != nil {
                runtimeHighlightCancellationCount += 1
                runtimeHighlightState = "cancelled"
                RuntimeDiagnosticsService.shared.record(
                    category: "editor",
                    name: "highlightCancelled",
                    correlationID: runtimeDiagnosticID
                )
            }
            highlightTask?.cancel()
            highlightTask = nil
            guard FileHighlightPolicy.usesSyntaxHighlighting(byteCount: text.utf8.count) else {
                return
            }

            let languageName = language?.rawValue
            runtimeHighlightState = "running"
            runtimeHighlightStartedAt = Self.runtimeNow()
            RuntimeDiagnosticsService.shared.record(
                category: "editor",
                name: "highlightStarted",
                correlationID: runtimeDiagnosticID
            )
            let highlightSignpost = RuntimeSignposts.signposter.beginInterval("SyntaxHighlight")
            highlightTask = Task { [weak self] in
                defer {
                    RuntimeSignposts.signposter.endInterval("SyntaxHighlight", highlightSignpost)
                }
                do {
                    if delayed {
                        try await Task.sleep(nanoseconds: Self.highlightDelay)
                    }
                    guard !Task.isCancelled else { return }
                    let highlightedText = try await Self.highlightService.highlight(
                        text,
                        languageName: languageName,
                        usesDarkAppearance: self?.usesDarkAppearance == true
                    )
                    guard !Task.isCancelled else { return }
                    self?.apply(
                        highlightedText: highlightedText,
                        sourceText: text,
                        expectedGeneration: expectedGeneration
                    )
                } catch {
                    guard let self, self.highlightGeneration == expectedGeneration else { return }
                    if error is CancellationError {
                        self.runtimeHighlightState = "cancelled"
                    } else {
                        self.runtimeHighlightState = "failed"
                        RuntimeDiagnosticsService.shared.record(
                            category: "editor",
                            name: "highlightFailed",
                            correlationID: self.runtimeDiagnosticID
                        )
                    }
                    return
                }
            }
        }

        @MainActor
        private func apply(
            highlightedText: AttributedString,
            sourceText: String,
            expectedGeneration: Int
        ) {
            // cachedText shares its buffer with the string the highlight was
            // requested for, so this stale-check is O(1) on the common path and
            // never rematerializes the whole document.
            guard highlightGeneration == expectedGeneration,
                  cachedText == sourceText,
                  let textView,
                  let textStorage = textView.textStorage else { return }
            let nativeHighlight = NSAttributedString(highlightedText)
            let storageLength = textStorage.length
            // The highlighter trims outer whitespace; locate the trimmed span so
            // color runs land on the right document offsets.
            let sourceRange = (sourceText as NSString).range(of: nativeHighlight.string)
            let baseColor = AppKitThemeAdapter.foreground
            // Recolor the live text storage in place instead of replacing the
            // whole string. Foreground color does not change glyph metrics, so
            // layout stays valid and no re-layout is needed.
            textStorage.beginEditing()
            textStorage.addAttribute(
                .foregroundColor,
                value: baseColor,
                range: NSRange(location: 0, length: storageLength)
            )
            if sourceRange.location != NSNotFound {
                nativeHighlight.enumerateAttribute(
                    .foregroundColor,
                    in: NSRange(location: 0, length: nativeHighlight.length)
                ) { value, range, _ in
                    guard let value else { return }
                    let target = NSRange(
                        location: sourceRange.location + range.location,
                        length: range.length
                    )
                    guard NSMaxRange(target) <= storageLength else { return }
                    textStorage.addAttribute(.foregroundColor, value: value, range: target)
                }
            }
            textStorage.endEditing()
            runtimeHighlightDurationMs = max(0, Self.runtimeNow() - runtimeHighlightStartedAt) * 1_000
            runtimeHighlightState = "idle"
            highlightTask = nil
            RuntimeDiagnosticsService.shared.record(
                category: "editor",
                name: "highlightCompleted",
                durationMs: runtimeHighlightDurationMs,
                correlationID: runtimeDiagnosticID
            )
        }

        @MainActor
        private func apply(_ text: NSAttributedString) {
            guard let scrollView,
                  let textView = scrollView.documentView as? NSTextView,
                  let textStorage = textView.textStorage else { return }
            let applyStartedAt = Self.runtimeNow()
            let signpost = RuntimeSignposts.signposter.beginInterval("TextApply")
            defer {
                RuntimeSignposts.signposter.endInterval("TextApply", signpost)
                runtimeTextApplyDurationMs = max(0, Self.runtimeNow() - applyStartedAt) * 1_000
                RuntimeDiagnosticsService.shared.record(
                    category: "editor",
                    name: "textApplied",
                    durationMs: runtimeTextApplyDurationMs,
                    metadata: ["bytes": .integer(runtimeContentBytes)],
                    correlationID: runtimeDiagnosticID
                )
            }
            let origin = scrollView.contentView.bounds.origin
            let selection = textView.selectedRange()
            let string = text.string
            cachedText = string
            updateRuntimeContentMetrics(string)
            beginRuntimeLayoutGrace()
            isApplyingText = true
            textStorage.setAttributedString(text)
            isApplyingText = false
            lineNumberView?.updateLineStarts(for: string)
            let length = (string as NSString).length
            if selection.location <= length {
                textView.setSelectedRange(
                    NSRange(
                        location: selection.location,
                        length: min(selection.length, length - selection.location)
                    )
                )
            }
            updateSelectionState(textView)
            scrollView.contentView.scroll(to: origin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        @MainActor
        private func applyFont() {
            guard renderedScale != 0,
                  let textView = scrollView?.documentView as? NSTextView,
                  let textStorage = textView.textStorage else { return }
            let font = font
            textView.font = font
            textStorage.addAttribute(
                .font,
                value: font,
                range: NSRange(location: 0, length: textStorage.length)
            )
            lineNumberView?.numberFont = font
        }

        @MainActor
        private func applyWordWrap(isEnabled: Bool) {
            guard let scrollView,
                  let textView = scrollView.documentView as? NSTextView,
                  let textContainer = textView.textContainer else { return }
            scrollView.hasHorizontalScroller = !isEnabled
            textView.isHorizontallyResizable = !isEnabled
            if isEnabled {
                textView.autoresizingMask = [.width]
                textContainer.widthTracksTextView = true
                textView.maxSize = NSSize(
                    width: CGFloat.greatestFiniteMagnitude,
                    height: CGFloat.greatestFiniteMagnitude
                )
                let width = scrollView.contentSize.width
                textContainer.size = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
                textView.setFrameSize(NSSize(width: width, height: textView.frame.height))
                scrollView.contentView.scroll(
                    to: NSPoint(x: 0, y: scrollView.contentView.bounds.minY)
                )
                scrollView.reflectScrolledClipView(scrollView.contentView)
            } else {
                textView.autoresizingMask = []
                textContainer.widthTracksTextView = false
                textContainer.size = NSSize(
                    width: CGFloat.greatestFiniteMagnitude,
                    height: CGFloat.greatestFiniteMagnitude
                )
            }
            textView.needsLayout = true
            textView.needsDisplay = true
            lineNumberView?.needsDisplay = true
        }

        func recordScrollInput(beforeY: Double, afterY: Double, deltaY: Double) {
            rollRuntimeWindowIfNeeded()
            runtimeScrollInputs += 1
            let maximumY = maximumRuntimeScrollY
            let eligible = abs(deltaY) > 0.01
                && maximumY > 1
                && beforeY > 1
                && beforeY < maximumY - 1
            if abs(afterY - beforeY) > 0.5 {
                runtimeBoundsChanges += 1
                runtimeLastBoundsOriginY = afterY
            } else if eligible {
                runtimeEligibleNoMovementInputs += 1
            }
        }

        func runtimeSnapshot() -> RuntimeEditorSnapshot {
            rollRuntimeWindowIfNeeded()
            let now = Self.runtimeNow()
            let useCompletedWindow = now - runtimeCompletedWindowAt < 1.5
            let clipBounds = scrollView?.contentView.bounds ?? .zero
            let documentHeight = scrollView?.documentView?.frame.height ?? 0
            let maximumY = max(0, documentHeight - clipBounds.height)
            return RuntimeEditorSnapshot(
                selectedControllerID: runtimeDiagnosticID,
                contentBytes: runtimeContentBytes,
                lineCount: runtimeLineCount,
                viewportOriginY: clipBounds.origin.y,
                viewportHeight: clipBounds.height,
                documentHeight: documentHeight,
                maximumScrollY: maximumY,
                canScrollVertically: maximumY > 1,
                scrollInputsWindow: useCompletedWindow
                    ? runtimeCompletedScrollInputs : runtimeScrollInputs,
                boundsChangesWindow: useCompletedWindow
                    ? runtimeCompletedBoundsChanges : runtimeBoundsChanges,
                eligibleNoMovementInputsWindow: useCompletedWindow
                    ? runtimeCompletedEligibleNoMovementInputs : runtimeEligibleNoMovementInputs,
                documentHeightChangesWindow: useCompletedWindow
                    ? runtimeCompletedDocumentHeightChanges : runtimeDocumentHeightChanges,
                highlightState: runtimeHighlightState,
                highlightDurationMs: runtimeHighlightDurationMs,
                highlightCancellationCount: runtimeHighlightCancellationCount,
                textApplyDurationMs: runtimeTextApplyDurationMs,
                attached: scrollView != nil && textView != nil
            )
        }

        func runScrollProbe(delta: Double, restore: Bool) async -> (
            status: String,
            elapsedMs: Double,
            result: [String: RuntimeScalar]
        ) {
            guard let scrollView else {
                return ("notApplicable", 0, ["reason": .string("Editor is not attached.")])
            }
            let maximumY = maximumRuntimeScrollY
            let originalOrigin = scrollView.contentView.bounds.origin
            let beforeY = originalOrigin.y
            guard maximumY > 1 else {
                return ("notApplicable", 0, ["reason": .string("Editor has no vertical scroll range.")])
            }
            let targetY = min(max(0, beforeY + delta), maximumY)
            guard abs(targetY - beforeY) > 0.5 else {
                return ("notApplicable", 0, ["reason": .string("Requested scroll is already at an edge.")])
            }
            let startedAt = Self.runtimeNow()
            let signpost = RuntimeSignposts.signposter.beginInterval("ActiveProbe")
            defer {
                if restore {
                    scrollView.contentView.scroll(to: originalOrigin)
                    scrollView.reflectScrolledClipView(scrollView.contentView)
                }
                RuntimeSignposts.signposter.endInterval("ActiveProbe", signpost)
            }
            scrollView.contentView.scroll(to: NSPoint(x: originalOrigin.x, y: targetY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            await Task.yield()
            let afterY = scrollView.contentView.bounds.origin.y
            let elapsedMs = max(0, Self.runtimeNow() - startedAt) * 1_000
            return (
                "ok",
                elapsedMs,
                [
                    "originBeforeY": .double(beforeY),
                    "originAfterY": .double(afterY),
                    "movementY": .double(afterY - beforeY),
                    "maximumScrollY": .double(maximumY),
                    "restored": .boolean(restore)
                ]
            )
        }

        private func recordBoundsChange() {
            rollRuntimeWindowIfNeeded()
            guard let scrollView else { return }
            let bounds = scrollView.contentView.bounds
            if abs(bounds.width - runtimeLastViewportWidth) > 1 {
                runtimeLastViewportWidth = bounds.width
                beginRuntimeLayoutGrace()
            }
            if abs(bounds.origin.y - runtimeLastBoundsOriginY) > 0.5 {
                runtimeBoundsChanges += 1
                runtimeLastBoundsOriginY = bounds.origin.y
            }
        }

        private func recordDocumentHeightChange() {
            rollRuntimeWindowIfNeeded()
            guard let height = scrollView?.documentView?.frame.height else { return }
            defer { runtimeLastDocumentHeight = height }
            guard abs(height - runtimeLastDocumentHeight) > 1,
                  Self.runtimeNow() >= runtimeLayoutGraceUntil else { return }
            runtimeDocumentHeightChanges += 1
            RuntimeDiagnosticsService.shared.record(
                category: "editor",
                name: "documentHeightChangedWithoutContentChange",
                metadata: [
                    "from": .double(runtimeLastDocumentHeight),
                    "to": .double(height)
                ],
                correlationID: runtimeDiagnosticID
            )
        }

        private func rollRuntimeWindowIfNeeded() {
            let now = Self.runtimeNow()
            guard now - runtimeWindowStartedAt >= 1 else { return }
            if runtimeEligibleNoMovementInputs >= 3 && runtimeBoundsChanges == 0 {
                RuntimeDiagnosticsService.shared.record(
                    category: "editor",
                    name: "scrollAnomalyWindowDetected",
                    metadata: [
                        "inputs": .integer(runtimeScrollInputs),
                        "eligibleNoMovement": .integer(runtimeEligibleNoMovementInputs)
                    ],
                    correlationID: runtimeDiagnosticID
                )
            }
            runtimeCompletedScrollInputs = runtimeScrollInputs
            runtimeCompletedBoundsChanges = runtimeBoundsChanges
            runtimeCompletedEligibleNoMovementInputs = runtimeEligibleNoMovementInputs
            runtimeCompletedDocumentHeightChanges = runtimeDocumentHeightChanges
            runtimeCompletedWindowAt = now
            runtimeWindowStartedAt = now
            runtimeScrollInputs = 0
            runtimeBoundsChanges = 0
            runtimeEligibleNoMovementInputs = 0
            runtimeDocumentHeightChanges = 0
        }

        private func beginRuntimeLayoutGrace() {
            runtimeLayoutGraceUntil = Self.runtimeNow() + 1
        }

        private func updateRuntimeContentMetrics(_ text: String) {
            runtimeContentBytes = text.utf8.count
            runtimeLineCount = text.isEmpty ? 0 : text.utf8.reduce(into: 1) { count, byte in
                if byte == 0x0A { count += 1 }
            }
        }

        private var maximumRuntimeScrollY: Double {
            guard let scrollView else { return 0 }
            return max(0, (scrollView.documentView?.frame.height ?? 0) - scrollView.contentView.bounds.height)
        }

        private static func runtimeNow() -> Double {
            Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
        }

        @MainActor
        private func baseAttributes(foregroundColor: NSColor) -> [NSAttributedString.Key: Any] {
            [
                .font: font,
                .foregroundColor: foregroundColor
            ]
        }

        @MainActor
        private var backingScale: CGFloat {
            renderedDisplayScale > 0 ? renderedDisplayScale : 2
        }

        @MainActor
        private var font: NSFont {
            AtelierTypography.codeFont(
                size: AtelierFontScaling.snapped(
                    AtelierTypography.editorSize * renderedScale,
                    displayScale: backingScale
                )
            )
        }

        private var lineNumberView: FileLineNumberRulerView? {
            scrollView?.verticalRulerView as? FileLineNumberRulerView
        }

        private func updateSelectionState(_ textView: NSTextView) {
            let selection = textView.selectedRange()
            // A caret (empty selection) yields no line range; skip the cached
            // text entirely so plain cursor moves stay O(1).
            guard selection.length > 0 else {
                surfaceOwner?.updateSelection(text: "", range: selection)
                return
            }
            surfaceOwner?.updateSelection(text: cachedText, range: selection)
        }
    }
}

private extension FileContent {
    var isEditableText: Bool {
        if case .text = self { return true }
        return false
    }
}

private enum FileViewerLanguage {
    static func language(for url: URL) -> HighlightLanguage? {
        switch url.lastPathComponent.lowercased() {
        case "dockerfile": return .dockerfile
        case "makefile": return .makefile
        default: break
        }

        switch url.pathExtension.lowercased() {
        case "ts", "tsx", "mts", "cts": return .typeScript
        case "js", "jsx", "mjs", "cjs": return .javaScript
        case "swift": return .swift
        case "json", "jsonc": return .json
        case "md", "markdown": return .markdown
        case "yml", "yaml": return .yaml
        case "html", "htm": return .html
        case "css": return .css
        case "scss": return .scss
        case "less": return .less
        case "sh", "bash", "zsh": return .bash
        case "py": return .python
        case "rb": return .ruby
        case "rs": return .rust
        case "go": return .go
        case "java": return .java
        case "kt", "kts": return .kotlin
        case "sql": return .sql
        case "toml": return .toml
        case "c", "h": return .c
        case "cc", "cpp", "cxx", "hpp": return .cPlusPlus
        case "cs": return .cSharp
        case "m", "mm": return .objectiveC
        case "diff", "patch": return .diff
        default: return nil
        }
    }
}
