import HighlightSwift
import SwiftUI

struct FileViewer: View {
    let content: FileContent
    let language: HighlightLanguage?

    private let displayText: String
    private let contentIdentity: FileViewerContentIdentity

    init(content: FileContent, fileURL: URL? = nil, language: HighlightLanguage? = nil) {
        self.content = content
        self.language = language ?? fileURL.flatMap(FileViewerLanguage.language(for:))
        displayText = content.displayText
        contentIdentity = FileViewerContentIdentity(content)
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical]) {
                highlightedText
                    .atelierFont(size: 12.5, design: .monospaced)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(
                        minWidth: geometry.size.width,
                        minHeight: geometry.size.height,
                        alignment: .topLeading
                    )
            }
            .atelierScrollChrome(backgroundColor: AtelierNativePalette.code)
        }
        .id(contentIdentity)
        .background(Color(nsColor: AtelierNativePalette.code))
    }

    @ViewBuilder
    private var highlightedText: some View {
        if case .text = content {
            if let language {
                CodeText(displayText)
                    .highlightLanguage(language)
                    .codeTextColors(.theme(.xcode))
            } else {
                CodeText(displayText)
                    .codeTextColors(.theme(.xcode))
            }
        } else {
            Text(displayText)
                .foregroundStyle(.secondary)
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

private struct FileViewerContentIdentity: Hashable {
    private let kind: Int
    private let byteCount: Int
    private let fingerprint: Int

    init(_ content: FileContent) {
        switch content {
        case .text(let text):
            kind = 0
            byteCount = text.utf8.count
            fingerprint = text.hashValue
        case .binary:
            kind = 1
            byteCount = 0
            fingerprint = 0
        case .tooLarge(let bytes):
            kind = 2
            byteCount = bytes
            fingerprint = bytes.hashValue
        case .error(let message):
            kind = 3
            byteCount = message.utf8.count
            fingerprint = message.hashValue
        }
    }
}
