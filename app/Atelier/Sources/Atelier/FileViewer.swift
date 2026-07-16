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

    init(content: FileContent, fileURL: URL? = nil, language: HighlightLanguage? = nil) {
        self.content = content
        self.fileURL = fileURL
        self.language = language ?? fileURL.flatMap(FileViewerLanguage.language(for:))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = STTextView.scrollableTextView()
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
        textView.backgroundColor = AtelierNativePalette.code
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.showsLineNumbers = true
        textView.gutterView?.drawSeparator = true
        textView.gutterView?.minimumThickness = 46
        textView.gutterView?.textColor = AtelierNativePalette.secondary
        textView.gutterView?.separatorColor = AtelierNativePalette.border

        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = AtelierNativePalette.code
        scrollView.scrollerStyle = .overlay
        context.coordinator.attach(scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.update(
            content: content,
            fileURL: fileURL,
            language: language,
            scale: scale
        )
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency STTextViewDelegate, @unchecked Sendable {
        private static let highlighter = Highlight()
        private static let saveDelay: UInt64 = 350_000_000
        private static let highlightDelay: UInt64 = 450_000_000

        private weak var scrollView: NSScrollView?
        private weak var textView: STTextView?
        private var renderedContent: FileContent?
        private var fileURL: URL?
        private var language: HighlightLanguage?
        private var renderedLanguage: String?
        private var renderedScale: CGFloat = 0
        private var highlightGeneration = 0
        private var highlightTask: Task<Void, Never>?
        private var saveGeneration = 0
        private var saveTask: Task<Void, Never>?
        private var isApplyingText = false

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
            scale: CGFloat
        ) {
            let contentChanged = renderedContent != content
                || renderedLanguage != language?.rawValue
            let scaleChanged = renderedScale != scale
            self.fileURL = fileURL
            self.language = language
            renderedScale = scale
            textView?.isEditable = fileURL != nil && content.isEditableText
            textView?.allowsUndo = textView?.isEditable == true

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
                foregroundColor = AtelierNativePalette.foreground
            case .loading, .binary, .tooLarge, .error:
                isText = false
                foregroundColor = AtelierNativePalette.secondary
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
                    try await FileSaver.saveAsync(text: text, url: url)
                    guard !Task.isCancelled,
                          self?.saveGeneration == expectedGeneration else { return }
                    self?.textView?.toolTip = nil
                } catch {
                    guard !(error is CancellationError),
                          self?.saveGeneration == expectedGeneration else { return }
                    self?.textView?.toolTip = "Auto-save failed: \(error.localizedDescription)"
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

            let mode = language.map(HighlightMode.language) ?? .automatic
            highlightTask = Task.detached(priority: .userInitiated) { [weak self] in
                do {
                    if delayed {
                        try await Task.sleep(nanoseconds: Self.highlightDelay)
                    }
                    guard !Task.isCancelled else { return }
                    let result = try await Self.highlighter.request(
                        text,
                        mode: mode,
                        colors: .light(.xcode)
                    )
                    guard !Task.isCancelled else { return }
                    await self?.apply(
                        highlightedText: result.attributedText,
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
                    foregroundColor: AtelierNativePalette.foreground
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
