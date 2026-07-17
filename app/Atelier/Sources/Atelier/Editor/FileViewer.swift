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

struct FileViewer: NSViewRepresentable {
    @Environment(\.atelierZoomScale) private var scale

    let content: FileContent
    let fileURL: URL?
    let language: HighlightLanguage?
    let isWordWrapEnabled: Bool

    init(
        content: FileContent,
        fileURL: URL? = nil,
        language: HighlightLanguage? = nil,
        isWordWrapEnabled: Bool = true
    ) {
        self.content = content
        self.fileURL = fileURL
        self.language = language ?? fileURL.flatMap(FileViewerLanguage.language(for:))
        self.isWordWrapEnabled = isWordWrapEnabled
    }

    func makeCoordinator() -> NativeEditorController {
        NativeEditorController()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = ResponsiveFileTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? STTextView else {
            return scrollView
        }

        textView.isEditable = false
        textView.isSelectable = true
        textView.allowsUndo = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.backgroundColor = AppKitThemeAdapter.code
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.showsLineNumbers = true
        if let gutterView = textView.gutterView {
            gutterView.drawSeparator = true
            gutterView.minimumThickness = 46
            gutterView.frame.size.width = max(gutterView.frame.width, gutterView.minimumThickness)
            gutterView.textColor = AppKitThemeAdapter.secondary
            gutterView.separatorColor = AppKitThemeAdapter.border
            textView.setFrameSize(textView.frame.size)
        }

        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = AppKitThemeAdapter.code
        scrollView.scrollerStyle = .overlay
        scrollView.clipsToBounds = true
        scrollView.contentView.clipsToBounds = true
        context.coordinator.attach(scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.update(
            content: content,
            fileURL: fileURL,
            language: language,
            scale: scale,
            isWordWrapEnabled: isWordWrapEnabled
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
        private var renderedWordWrapEnabled: Bool?
        private var highlightGeneration = 0
        private var highlightTask: Task<Void, Never>?
        private var saveGeneration = 0
        private var saveTask: Task<Void, Never>?
        private var isApplyingText = false
        private(set) var document: EditorDocument?

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
            isWordWrapEnabled: Bool
        ) {
            let contentChanged = renderedContent != content
                || renderedLanguage != language?.rawValue
            let scaleChanged = renderedScale != scale
            let wordWrapChanged = renderedWordWrapEnabled != isWordWrapEnabled
            self.fileURL = fileURL
            if let fileURL {
                open(EditorDocument(url: fileURL))
            } else {
                document = nil
            }
            self.language = language
            renderedScale = scale
            renderedWordWrapEnabled = isWordWrapEnabled
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
            textView = nil
            scrollView = nil
            document = nil
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

        func textViewDidChangeText(_ notification: Notification) {
            guard !isApplyingText,
                  let textView = notification.object as? STTextView,
                  let fileURL else { return }
            let text = textView.text ?? ""
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
            case .loading, .binary, .tooLarge, .error:
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
                        languageName: languageName
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
            guard highlightGeneration == expectedGeneration,
                  textView?.text == sourceText else { return }
            let nativeHighlight = NSAttributedString(highlightedText)
            let nativeText = NSMutableAttributedString(
                string: sourceText,
                attributes: baseAttributes(
                    foregroundColor: AppKitThemeAdapter.foreground
                )
            )
            let sourceRange = (sourceText as NSString).range(of: nativeHighlight.string)
            if sourceRange.location != NSNotFound {
                nativeHighlight.enumerateAttribute(
                    .foregroundColor,
                    in: NSRange(location: 0, length: nativeHighlight.length)
                ) { value, range, _ in
                    guard let value else { return }
                    nativeText.addAttribute(
                        .foregroundColor,
                        value: value,
                        range: NSRange(
                            location: sourceRange.location + range.location,
                            length: range.length
                        )
                    )
                }
            }
            apply(nativeText)
        }

        @MainActor
        private func apply(_ text: NSAttributedString) {
            guard let scrollView,
                  let textView = scrollView.documentView as? STTextView else { return }
            let origin = scrollView.contentView.bounds.origin
            let selection = textView.textSelection
            isApplyingText = true
            textView.attributedText = text
            isApplyingText = false
            if selection.location <= text.length {
                textView.textSelection = NSRange(
                    location: selection.location,
                    length: min(selection.length, text.length - selection.location)
                )
            }
            scrollView.contentView.scroll(to: origin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        @MainActor
        private func applyFont() {
            guard renderedScale != 0,
                  let textView = scrollView?.documentView as? STTextView else { return }
            textView.font = font
            textView.gutterView?.font = .monospacedDigitSystemFont(
                ofSize: 10.5 * renderedScale,
                weight: .regular
            )
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
        }

        @MainActor
        private func baseAttributes(foregroundColor: NSColor) -> [NSAttributedString.Key: Any] {
            [
                .font: font,
                .foregroundColor: foregroundColor
            ]
        }

        @MainActor
        private var font: NSFont {
            .monospacedSystemFont(ofSize: 12.5 * renderedScale, weight: .regular)
        }
    }
}

private final class ResponsiveFileTextView: STTextView {
    override class var isCompatibleWithResponsiveScrolling: Bool {
        true
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
