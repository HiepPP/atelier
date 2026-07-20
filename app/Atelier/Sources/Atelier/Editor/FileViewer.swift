import AppKit
import HighlightSwift
import STTextView
import SwiftUI

enum FileHighlightPolicy {
    static let maximumHighlightedBytes = 200_000

    static func usesSyntaxHighlighting(byteCount: Int) -> Bool {
        byteCount <= maximumHighlightedBytes
    }
}

enum FileLayoutPolicy {
    // TextKit 2 estimates document height while scrolling. Every previewable
    // text file is small enough to measure once and keep its scroller stable.
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
    let isWordWrapEnabled: Bool
    let surfaceOwner: EditorSession?
    let onEdit: () -> Void

    init(
        content: FileContent,
        fileURL: URL? = nil,
        language: HighlightLanguage? = nil,
        isWordWrapEnabled: Bool = true,
        surfaceOwner: EditorSession? = nil,
        onEdit: @escaping () -> Void = {}
    ) {
        self.content = content
        self.fileURL = fileURL
        self.language = language ?? fileURL.flatMap(FileViewerLanguage.language(for:))
        self.isWordWrapEnabled = isWordWrapEnabled
        self.surfaceOwner = surfaceOwner
        self.onEdit = onEdit
    }

    func makeCoordinator() -> NativeEditorController {
        NativeEditorController()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = StableFileTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? STTextView else {
            return scrollView
        }

        textView.isEditable = false
        textView.isSelectable = true
        textView.isIncrementalSearchingEnabled = true
        textView.textFinder.incrementalSearchingShouldDimContentView = false
        textView.allowsUndo = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.backgroundColor = AppKitThemeAdapter.code
        textView.insertionPointColor = AppKitThemeAdapter.accent
        textView.textContainer.lineFragmentPadding = AtelierMetrics.spaceM
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.showsLineNumbers = true
        if let gutterView = textView.gutterView {
            gutterView.drawSeparator = true
            gutterView.minimumThickness = AtelierMetrics.codeGutterWidth
            gutterView.frame.size.width = max(gutterView.frame.width, gutterView.minimumThickness)
            gutterView.textColor = AppKitThemeAdapter.secondary
            gutterView.separatorColor = AppKitThemeAdapter.border
            let lineNumberView = FileLineNumberRulerView(
                scrollView: scrollView,
                textView: textView,
                gutterView: gutterView
            )
            gutterView.addSubview(
                lineNumberView,
                positioned: .below,
                relativeTo: gutterView.subviews.last
            )
            textView.setFrameSize(textView.frame.size)
        }

        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = AppKitThemeAdapter.code
        scrollView.scrollerStyle = .overlay
        scrollView.contentInsets = NSEdgeInsets(
            top: AtelierMetrics.spaceM,
            left: 0,
            bottom: AtelierMetrics.spaceM,
            right: 0
        )
        scrollView.clipsToBounds = true
        scrollView.contentView.clipsToBounds = true
        context.coordinator.attach(scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let usesDarkAppearance = colorScheme == .dark
        if context.coordinator.appliedBackgroundIsDark != usesDarkAppearance {
            context.coordinator.appliedBackgroundIsDark = usesDarkAppearance
            let background = AppKitThemeAdapter.editor(
                usesDarkAppearance: usesDarkAppearance
            )
            scrollView.backgroundColor = background
            if let textView = scrollView.documentView as? STTextView {
                textView.backgroundColor = background
                textView.gutterView?.subviews
                    .compactMap { $0 as? FileLineNumberRulerView }
                    .first?.backgroundColor = background
            }
        }
        context.coordinator.update(
            content: content,
            fileURL: fileURL,
            language: language,
            scale: scale,
            displayScale: displayScale,
            usesDarkAppearance: usesDarkAppearance,
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
    final class NativeEditorController: NSObject, @preconcurrency STTextViewDelegate, EditorSurface {
        private static let highlightService = SyntaxHighlightService()
        private static let saveDelay: UInt64 = 350_000_000
        private static let highlightDelay: UInt64 = 450_000_000

        private weak var scrollView: NSScrollView?
        private weak var textView: STTextView?
        private var renderedContent: FileContent?
        private var fileURL: URL?
        private var language: HighlightLanguage?
        private var renderedLanguage: String?
        private var renderedScale: CGFloat = 0
        private var renderedDisplayScale: CGFloat = 0
        private var usesDarkAppearance = false
        private var renderedWordWrapEnabled: Bool?
        private var highlightGeneration = 0
        private var highlightTask: Task<Void, Never>?
        private var saveGeneration = 0
        private var saveTask: Task<Void, Never>?
        private var isApplyingText = false
        // Mirror of the current document text, kept in sync on content set and on
        // edit. Selection changes read this instead of rematerializing the whole
        // STTextView document string on every cursor move.
        private var cachedText = ""
        private weak var surfaceOwner: EditorSession?
        private var onEdit: () -> Void = {}
        private(set) var document: EditorDocument?
        // Tracks the applied background so updateNSView skips redundant
        // AppKit writes on unrelated SwiftUI updates.
        var appliedBackgroundIsDark: Bool?

        func attach(_ scrollView: NSScrollView) {
            self.scrollView = scrollView
            guard let textView = scrollView.documentView as? STTextView else { return }
            self.textView = textView
            textView.textDelegate = self
        }

        @MainActor
        func update(
            content: FileContent,
            fileURL: URL?,
            language: HighlightLanguage?,
            scale: CGFloat,
            displayScale: CGFloat,
            usesDarkAppearance: Bool,
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
            renderedWordWrapEnabled = isWordWrapEnabled
            if self.surfaceOwner !== surfaceOwner {
                self.surfaceOwner?.detach(surface: self)
                self.surfaceOwner = surfaceOwner
                surfaceOwner?.attach(surface: self)
            }
            self.onEdit = onEdit
            textView?.isEditable = fileURL != nil && content.isEditableText
            textView?.allowsUndo = textView?.isEditable == true

            if wordWrapChanged {
                applyWordWrap(isEnabled: isWordWrapEnabled)
            }
            if scaleChanged {
                applyFont()
            }
            if contentChanged {
                renderedContent = content
                renderedLanguage = language?.rawValue
                render(content: content, language: language)
            }
        }

        @MainActor
        func stop() {
            highlightGeneration += 1
            highlightTask?.cancel()
            highlightTask = nil
            saveGeneration += 1
            saveTask?.cancel()
            saveTask = nil
            textView?.textDelegate = nil
            surfaceOwner?.detach(surface: self)
            surfaceOwner = nil
            textView = nil
            scrollView = nil
            document = nil
            onEdit = {}
        }

        func open(_ document: EditorDocument) {
            self.document = document
            fileURL = document.url
        }

        func save() async throws {
            guard let text = textView?.text, let fileURL else { return }
            try await FileSaver.saveAsync(text: text, url: fileURL)
        }

        func reveal(line: Int, column: Int) {
            guard line > 0, column > 0, let text = textView?.text else { return }
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            guard line <= lines.count else { return }
            let prefixLength = lines.prefix(line - 1).reduce(0) { $0 + $1.utf16.count + 1 }
            let location = min(prefixLength + column - 1, text.utf16.count)
            textView?.textSelection = NSRange(location: location, length: 0)
            textView?.scrollRangeToVisible(NSRange(location: location, length: 0))
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
            guard textView.textFinder.validateAction(finderAction) else { return }
            textView.textFinder.performAction(finderAction)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView,
                  notification.object as? STTextView === textView else { return }
            updateSelectionState(textView)
            guard scrollView?.isFindBarVisible == true else { return }
            lineNumberView?.scheduleVisibleLineRefresh()
            if let textView = textView as? StableFileTextView {
                textView.prepareForFindRelocation()
            }
        }

        func textViewDidChangeText(_ notification: Notification) {
            guard !isApplyingText,
                  let textView = notification.object as? STTextView,
                  let fileURL else { return }
            let text = textView.text ?? ""
            cachedText = text
            lineNumberView?.updateText(text)
            // Editing changes line structure, so the pinned document height is
            // stale. Unfreeze now and re-measure after the burst settles.
            (textView as? StableFileTextView)?.invalidateStabilizedHeightForEdit()
            onEdit()
            scheduleSave(text: text, url: fileURL)
            scheduleHighlight(text: text, language: language, delayed: true)
        }

        @MainActor
        private func render(content: FileContent, language: HighlightLanguage?) {
            highlightGeneration += 1
            highlightTask?.cancel()
            highlightTask = nil

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
                    guard self?.textView?.text == text, self?.fileURL == url else { return }
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
            highlightTask?.cancel()
            highlightTask = nil
            guard FileHighlightPolicy.usesSyntaxHighlighting(byteCount: text.utf8.count) else {
                return
            }

            let languageName = language?.rawValue
            highlightTask = Task { [weak self] in
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
                  let textStorage = (textView.textContentManager as? NSTextContentStorage)?
                    .textStorage else { return }
            let nativeHighlight = NSAttributedString(highlightedText)
            let storageLength = textStorage.length
            // The highlighter trims outer whitespace; locate the trimmed span so
            // color runs land on the right document offsets.
            let sourceRange = (sourceText as NSString).range(of: nativeHighlight.string)
            let baseColor = AppKitThemeAdapter.foreground
            // Recolor the live text storage in place instead of replacing the
            // whole attributedText. Foreground color does not change glyph
            // metrics, so layout stays valid and no height re-measure is needed.
            textView.textContentManager.performEditingTransaction {
                textStorage.addAttribute(
                    .foregroundColor,
                    value: baseColor,
                    range: NSRange(location: 0, length: storageLength)
                )
                guard sourceRange.location != NSNotFound else { return }
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
            textView.needsLayout = true
        }

        @MainActor
        private func apply(_ text: NSAttributedString) {
            guard let scrollView,
                  let textView = scrollView.documentView as? STTextView else { return }
            let origin = scrollView.contentView.bounds.origin
            let selection = textView.textSelection
            let string = text.string
            cachedText = string
            isApplyingText = true
            textView.attributedText = text
            isApplyingText = false
            lineNumberView?.updateText(string)
            ensureStableDocumentHeight()
            if selection.location <= text.length {
                textView.textSelection = NSRange(
                    location: selection.location,
                    length: min(selection.length, text.length - selection.location)
                )
            }
            updateSelectionState(textView)
            scrollView.contentView.scroll(to: origin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        @MainActor
        private func ensureStableDocumentHeight() {
            guard let textView = textView as? StableFileTextView,
                  let text = textView.text,
                  FileLayoutPolicy.usesFullLayout(byteCount: text.utf8.count) else { return }
            textView.stabilizeDocumentHeight()
        }

        @MainActor
        private func applyFont() {
            guard renderedScale != 0,
                  let textView = scrollView?.documentView as? STTextView else { return }
            textView.font = font
            textView.gutterView?.font = AtelierTypography.codeFont(
                size: AtelierFontScaling.snapped(
                    AtelierTypography.editorSize * renderedScale,
                    displayScale: backingScale
                )
            )
            lineNumberView?.font = font
            ensureStableDocumentHeight()
        }

        @MainActor
        private func applyWordWrap(isEnabled: Bool) {
            guard let scrollView, let textView else { return }
            textView.isHorizontallyResizable = !isEnabled
            scrollView.hasHorizontalScroller = !isEnabled
            if isEnabled {
                scrollView.contentView.scroll(
                    to: NSPoint(x: 0, y: scrollView.contentView.bounds.minY)
                )
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
            textView.needsLayout = true
            textView.needsDisplay = true
            ensureStableDocumentHeight()
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
            textView?.gutterView?.subviews
                .compactMap { $0 as? FileLineNumberRulerView }
                .first
        }

        private func updateSelectionState(_ textView: STTextView) {
            let selection = textView.textSelection
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

private final class StableFileTextView: STTextView {
    private var stabilizedDocumentHeight: CGFloat?
    private var stabilizationTask: Task<Void, Never>?
    private var editHeightTask: Task<Void, Never>?
    private var allowsNextFindRelocationHeight = false
    private var findRelocationResetTask: Task<Void, Never>?

    // Height only depends on the text, font, wrap mode, and container width.
    // Highlight passes swap colors on identical text, so remembering the last
    // measured key lets those passes skip the full-document measurement.
    private struct MeasurementKey: Equatable {
        let text: String
        let width: CGFloat
        let font: NSFont
        let wraps: Bool
    }

    private var lastMeasurementKey: MeasurementKey?

    // One reusable measurement stack instead of a fresh TextKit1 stack per
    // measurement.
    private let measurementStorage = NSTextStorage()
    private let measurementContainer = NSTextContainer(
        size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
    )
    private lazy var measurementLayoutManager: NSLayoutManager = {
        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(measurementContainer)
        measurementStorage.addLayoutManager(layoutManager)
        return layoutManager
    }()

    override func setFrameSize(_ newSize: NSSize) {
        if allowsNextFindRelocationHeight {
            allowsNextFindRelocationHeight = false
            super.setFrameSize(newSize)
            return
        }
        guard let stabilizedDocumentHeight else {
            super.setFrameSize(newSize)
            return
        }

        let widthChanged = abs(newSize.width - frame.width) > 0.5
        if widthChanged, !isHorizontallyResizable {
            self.stabilizedDocumentHeight = nil
            super.setFrameSize(newSize)
            scheduleDocumentHeightStabilization()
            return
        }

        var stableSize = newSize
        stableSize.height = stabilizedDocumentHeight
        super.setFrameSize(stableSize)
    }

    func stabilizeDocumentHeight() {
        guard let attributedText else { return }

        let key = MeasurementKey(
            text: attributedText.string,
            width: textContainer.size.width,
            font: font,
            wraps: !isHorizontallyResizable
        )
        if let currentHeight = stabilizedDocumentHeight, key == lastMeasurementKey {
            // Text metrics unchanged (e.g. a highlight pass); keep the cached
            // measurement and only grow to fill a taller viewport.
            let viewportHeight = enclosingScrollView?.contentView.bounds.height ?? 0
            if viewportHeight > currentHeight {
                stabilizedDocumentHeight = viewportHeight
                super.setFrameSize(NSSize(width: frame.width, height: viewportHeight))
            }
            return
        }

        let layoutManager = measurementLayoutManager
        measurementContainer.size = NSSize(
            width: textContainer.size.width,
            height: .greatestFiniteMagnitude
        )
        measurementContainer.lineFragmentPadding = textContainer.lineFragmentPadding
        measurementStorage.setAttributedString(attributedText)
        layoutManager.ensureLayout(for: measurementContainer)

        let lineStarts = Self.lineStarts(in: attributedText.string)
        var measuredLineCenters = Array<CGFloat?>(
            repeating: nil,
            count: lineStarts.count
        )
        var logicalLineIndex = 0
        let glyphRange = NSRange(location: 0, length: layoutManager.numberOfGlyphs)
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) {
            lineRect,
            _,
            _,
            fragmentGlyphRange,
            _ in
            let characterRange = layoutManager.characterRange(
                forGlyphRange: fragmentGlyphRange,
                actualGlyphRange: nil
            )
            while logicalLineIndex + 1 < lineStarts.count,
                  lineStarts[logicalLineIndex + 1] <= characterRange.location {
                logicalLineIndex += 1
            }
            if measuredLineCenters[logicalLineIndex] == nil {
                measuredLineCenters[logicalLineIndex] = lineRect.midY
            }
        }

        if measuredLineCenters.last == nil,
           !layoutManager.extraLineFragmentRect.isEmpty {
            measuredLineCenters[measuredLineCenters.count - 1] =
                layoutManager.extraLineFragmentRect.midY
        }

        let lineHeight = layoutManager.defaultLineHeight(for: font)
        var nextLineCenter = lineHeight / 2
        let lineCenters = measuredLineCenters.map { measuredCenter in
            let center = measuredCenter ?? nextLineCenter
            nextLineCenter = center + lineHeight
            return center
        }

        let measuredHeight = ceil(layoutManager.usedRect(for: measurementContainer).height)
        let viewportHeight = enclosingScrollView?.contentView.bounds.height ?? 0
        let stableHeight = max(measuredHeight, viewportHeight)
        stabilizedDocumentHeight = stableHeight
        lastMeasurementKey = key
        // Drop the copied text once measured; the key keeps its own reference.
        measurementStorage.setAttributedString(NSAttributedString())
        super.setFrameSize(NSSize(width: frame.width, height: stableHeight))
        gutterView?.subviews
            .compactMap { $0 as? FileLineNumberRulerView }
            .first?.updateLineCenters(lineCenters)
    }

    private func scheduleDocumentHeightStabilization() {
        guard stabilizationTask == nil else { return }
        stabilizationTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            stabilizationTask = nil
            stabilizeDocumentHeight()
        }
    }

    // Called on every text edit. Unfreezes the pinned height so TextKit lays
    // the document out naturally while the user types, then re-measures once
    // after the typing burst settles. Coalesces rapid keystrokes into a single
    // full measurement instead of one per keystroke.
    func invalidateStabilizedHeightForEdit() {
        stabilizedDocumentHeight = nil
        editHeightTask?.cancel()
        editHeightTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled, let self else { return }
            editHeightTask = nil
            stabilizeDocumentHeight()
        }
    }

    func prepareForFindRelocation() {
        allowsNextFindRelocationHeight = true
        findRelocationResetTask?.cancel()
        findRelocationResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let self else { return }
            allowsNextFindRelocationHeight = false
            findRelocationResetTask = nil
        }
    }

    private static func lineStarts(in text: String) -> [Int] {
        var starts = [0]
        starts.reserveCapacity(max(1, text.utf16.count / 40))
        var offset = 0
        for codeUnit in text.utf16 {
            offset += 1
            if codeUnit == 0x0A {
                starts.append(offset)
            }
        }
        return starts
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
