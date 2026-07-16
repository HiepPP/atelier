import AppKit
import HighlightSwift
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
    let language: HighlightLanguage?

    init(content: FileContent, fileURL: URL? = nil, language: HighlightLanguage? = nil) {
        self.content = content
        self.language = language ?? fileURL.flatMap(FileViewerLanguage.language(for:))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.allowsUndo = false
        textView.drawsBackground = true
        textView.backgroundColor = AtelierNativePalette.code
        textView.textContainerInset = NSSize(width: 16, height: 14)
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 0
        textView.layoutManager?.allowsNonContiguousLayout = true

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
            language: language,
            scale: scale
        )
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator: @unchecked Sendable {
        private static let highlighter = Highlight()

        private weak var scrollView: NSScrollView?
        private var renderedContent: FileContent?
        private var renderedLanguage: String?
        private var renderedScale: CGFloat = 0
        private var generation = 0
        private var highlightTask: Task<Void, Never>?

        func attach(_ scrollView: NSScrollView) {
            self.scrollView = scrollView
        }

        @MainActor
        func update(content: FileContent, language: HighlightLanguage?, scale: CGFloat) {
            let contentChanged = renderedContent != content
                || renderedLanguage != language?.rawValue
            let scaleChanged = renderedScale != scale
            renderedScale = scale

            if contentChanged {
                renderedContent = content
                renderedLanguage = language?.rawValue
                render(content: content, language: language)
            } else if scaleChanged {
                applyFont()
            }
        }

        @MainActor
        func stop() {
            generation += 1
            highlightTask?.cancel()
            highlightTask = nil
            scrollView = nil
        }

        @MainActor
        private func render(content: FileContent, language: HighlightLanguage?) {
            generation += 1
            let expectedGeneration = generation
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

            let mode = language.map(HighlightMode.language) ?? .automatic
            highlightTask = Task.detached(priority: .userInitiated) { [weak self] in
                do {
                    let result = try await Self.highlighter.request(
                        text,
                        mode: mode,
                        colors: .light(.xcode)
                    )
                    guard !Task.isCancelled else { return }
                    await self?.apply(
                        highlightedText: result.attributedText,
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
            expectedGeneration: Int
        ) {
            guard generation == expectedGeneration else { return }
            let nativeText = NSMutableAttributedString(
                attributedString: NSAttributedString(highlightedText)
            )
            nativeText.addAttribute(
                .font,
                value: font,
                range: NSRange(location: 0, length: nativeText.length)
            )
            apply(nativeText)
        }

        @MainActor
        private func apply(_ text: NSAttributedString) {
            guard let scrollView,
                  let textView = scrollView.documentView as? NSTextView else { return }
            let origin = scrollView.contentView.bounds.origin
            let selection = textView.selectedRange()
            textView.textStorage?.setAttributedString(text)
            if selection.location <= text.length {
                textView.setSelectedRange(
                    NSRange(
                        location: selection.location,
                        length: min(selection.length, text.length - selection.location)
                    )
                )
            }
            scrollView.contentView.scroll(to: origin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        @MainActor
        private func applyFont() {
            guard renderedScale != 0,
                  let textView = scrollView?.documentView as? NSTextView,
                  let textStorage = textView.textStorage,
                  textStorage.length > 0 else { return }
            textStorage.addAttribute(
                .font,
                value: font,
                range: NSRange(location: 0, length: textStorage.length)
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
