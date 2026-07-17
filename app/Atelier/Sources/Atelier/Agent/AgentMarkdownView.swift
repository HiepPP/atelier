import AppKit
import SwiftUI

struct AgentMarkdownView: View {
    let source: String

    private var blocks: [AgentMarkdownBlock] {
        AgentMarkdownBlock.parse(source)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(blocks.indices, id: \.self) { index in
                blockView(blocks[index])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: AgentMarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let content):
            inlineText(content)
                .atelierFont(size: headingSize(level), weight: .semibold)
                .padding(.top, level <= 2 ? 3 : 1)
        case .paragraph(let content):
            inlineText(content)
                .atelierFont(size: 12.5)
                .lineSpacing(2)
        case .unorderedItem(let content):
            listRow(marker: "-", content: content)
        case .orderedItem(let number, let content):
            listRow(marker: "\(number).", content: content)
        case .quote(let content):
            inlineText(content)
                .atelierFont(size: 12.5)
                .foregroundStyle(.secondary)
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(AtelierTheme.border)
                        .frame(width: 2)
                }
        case .code(_, let content):
            codeBlock(content)
        case .mermaid(let source):
            MermaidResponseCard(source: source)
        case .divider:
            Divider()
        }
    }

    private func codeBlock(_ content: String) -> some View {
        let bounded = content.count > 8_000
            ? String(content.prefix(8_000)) + "\n..."
            : content
        return Text(bounded)
            .atelierFont(size: 11.5, design: .monospaced)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(AtelierTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: AtelierTheme.controlRadius))
    }

    private func listRow(marker: String, content: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(marker)
                .atelierFont(size: 12, design: .monospaced)
                .foregroundStyle(.secondary)
                .frame(minWidth: 18, alignment: .trailing)
            inlineText(content)
                .atelierFont(size: 12.5)
                .lineSpacing(2)
        }
    }

    private func inlineText(_ content: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        let attributed = (try? AttributedString(markdown: content, options: options))
            ?? AttributedString(content)
        return Text(attributed)
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: 18
        case 2: 16
        case 3: 14
        default: 12.5
        }
    }
}

struct MermaidResponseCard: View {
    let source: String

    @State private var image: NSImage?
    @State private var renderError: String?
    @State private var showsSource = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("Mermaid", systemImage: "point.3.connected.trianglepath.dotted")
                    .atelierFont(size: 10, weight: .semibold, design: .monospaced)
                    .foregroundStyle(AtelierTheme.accent)
                Spacer()
                Button(showsSource ? "Hide source" : "View source") {
                    showsSource.toggle()
                }
                .buttonStyle(.borderless)
                .atelierFont(size: 10)
            }

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let renderError {
                Label(renderError, systemImage: "exclamationmark.triangle")
                    .atelierFont(size: 10.5)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }

            if showsSource || renderError != nil {
                Text(source)
                    .atelierFont(size: 11, design: .monospaced)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(AtelierTheme.editor)
                    .clipShape(RoundedRectangle(cornerRadius: AtelierTheme.controlRadius))
            }
        }
        .padding(12)
        .background(AtelierTheme.panel)
        .overlay {
            RoundedRectangle(cornerRadius: AtelierTheme.controlRadius)
                .stroke(AtelierTheme.border, lineWidth: 0.75)
        }
        .clipShape(RoundedRectangle(cornerRadius: AtelierTheme.controlRadius))
        .task(id: source) {
            image = nil
            renderError = nil
            do {
                let png = try await MermaidImageRenderer().render(source: source, width: 960)
                guard !Task.isCancelled, let rendered = NSImage(data: png) else { return }
                image = rendered
            } catch {
                guard !Task.isCancelled else { return }
                renderError = "Diagram could not be rendered. Source is shown below."
            }
        }
    }
}

nonisolated enum AgentMarkdownBlock: Equatable, Sendable {
    case heading(level: Int, content: String)
    case paragraph(String)
    case unorderedItem(String)
    case orderedItem(number: Int, content: String)
    case quote(String)
    case code(language: String?, content: String)
    case mermaid(String)
    case divider

    static func parse(_ source: String) -> [Self] {
        var blocks: [Self] = []
        var paragraph: [String] = []
        var fencedLines: [String] = []
        var fenceMarker: String?
        var fenceLanguage: String?

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: " ")))
            paragraph.removeAll(keepingCapacity: true)
        }

        func flushFence() {
            let content = fencedLines.joined(separator: "\n")
            if fenceLanguage?.lowercased() == "mermaid" {
                blocks.append(.mermaid(content))
            } else {
                blocks.append(.code(language: fenceLanguage, content: content))
            }
            fencedLines.removeAll(keepingCapacity: true)
            fenceMarker = nil
            fenceLanguage = nil
        }

        for line in source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let fenceMarker {
                if trimmed == fenceMarker {
                    flushFence()
                } else {
                    fencedLines.append(line)
                }
                continue
            }

            if let opening = fenceOpening(trimmed) {
                flushParagraph()
                fenceMarker = opening.marker
                fenceLanguage = opening.language
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            if isDivider(trimmed) {
                flushParagraph()
                blocks.append(.divider)
                continue
            }

            if let heading = heading(from: trimmed) {
                flushParagraph()
                blocks.append(.heading(level: heading.level, content: heading.content))
                continue
            }

            if let content = prefixedContent(in: trimmed, prefixes: ["- ", "* ", "+ "]) {
                flushParagraph()
                blocks.append(.unorderedItem(content))
                continue
            }

            if let item = orderedItem(from: trimmed) {
                flushParagraph()
                blocks.append(.orderedItem(number: item.number, content: item.content))
                continue
            }

            if let content = prefixedContent(in: trimmed, prefixes: ["> "]) {
                flushParagraph()
                blocks.append(.quote(content))
                continue
            }

            paragraph.append(trimmed)
        }

        if fenceMarker != nil || !fencedLines.isEmpty {
            flushFence()
        }
        flushParagraph()
        return blocks
    }

    private static func fenceOpening(_ line: String) -> (marker: String, language: String?)? {
        let marker: String
        if line.hasPrefix("```") {
            marker = "```"
        } else if line.hasPrefix("~~~") {
            marker = "~~~"
        } else {
            return nil
        }
        let language = line.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
        return (marker, language.isEmpty ? nil : language)
    }

    private static func heading(from line: String) -> (level: Int, content: String)? {
        let level = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(level), line.dropFirst(level).first == " " else { return nil }
        return (level, String(line.dropFirst(level + 1)))
    }

    private static func orderedItem(from line: String) -> (number: Int, content: String)? {
        guard let delimiter = line.firstIndex(of: ".") else { return nil }
        let numberText = line[..<delimiter]
        let contentStart = line.index(after: delimiter)
        guard !numberText.isEmpty,
              numberText.allSatisfy(\.isNumber),
              contentStart < line.endIndex,
              line[contentStart] == " ",
              let number = Int(numberText) else {
            return nil
        }
        return (number, String(line[line.index(after: contentStart)...]))
    }

    private static func prefixedContent(in line: String, prefixes: [String]) -> String? {
        guard let prefix = prefixes.first(where: line.hasPrefix) else { return nil }
        return String(line.dropFirst(prefix.count))
    }

    private static func isDivider(_ line: String) -> Bool {
        guard line.count >= 3 else { return false }
        let characters = line.filter { !$0.isWhitespace }
        guard characters.count >= 3, let first = characters.first, "-_*".contains(first) else {
            return false
        }
        return characters.allSatisfy { $0 == first }
    }
}
