import AppKit
import SwiftUI

nonisolated enum AgentCodeBlockPolicy {
    static let displayLimit = 8_000

    static func displayedContent(_ source: String) -> String {
        guard source.count > displayLimit else { return source }
        return String(source.prefix(displayLimit)) + "\n..."
    }

    static func copiedContent(_ source: String) -> String {
        source
    }
}

nonisolated enum MermaidResponsePresentationPolicy {
    enum DisplayState: Equatable, Sendable {
        case loading
        case rendered
        case failed(String)
    }

    static func showsSource(userRequested: Bool, hasRenderError: Bool) -> Bool {
        userRequested || hasRenderError
    }

    static func displayState(hasImage: Bool, error: String?) -> DisplayState {
        if let error { return .failed(error) }
        return hasImage ? .rendered : .loading
    }
}

struct AgentMarkdownView: View {
    let source: String

    var body: some View {
        let blocks = AgentMarkdownBlock.parse(source)
        VStack(alignment: .leading, spacing: AtelierMetrics.spaceS) {
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
                .padding(.top, level <= 2 ? AtelierMetrics.spaceXS : 0)
                .frame(maxWidth: AtelierMetrics.transcriptMaxWidth, alignment: .leading)
        case .paragraph(let content):
            inlineText(content)
                .atelierFont(size: AtelierTypography.body)
                .lineSpacing(AtelierMetrics.spaceXS)
                .frame(maxWidth: AtelierMetrics.transcriptMaxWidth, alignment: .leading)
        case .unorderedItem(let content):
            listRow(marker: "-", content: content)
                .frame(maxWidth: AtelierMetrics.transcriptMaxWidth, alignment: .leading)
        case .orderedItem(let number, let content):
            listRow(marker: "\(number).", content: content)
                .frame(maxWidth: AtelierMetrics.transcriptMaxWidth, alignment: .leading)
        case .quote(let content):
            inlineText(content)
                .atelierFont(size: AtelierTypography.body)
                .foregroundStyle(.secondary)
                .padding(.leading, AtelierMetrics.spaceM)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(AtelierTheme.accent.opacity(0.72))
                        .frame(width: AtelierTheme.strokeFocus)
                }
                .frame(maxWidth: AtelierMetrics.transcriptMaxWidth, alignment: .leading)
        case .code(let language, let content):
            codeBlock(language: language, content: content)
        case .mermaid(let source):
            MermaidResponseCard(source: source)
        case .invalidMermaid(let source, let error):
            MermaidResponseCard(source: source, parseError: error)
        case .table(let headers, let rows):
            table(headers: headers, rows: rows)
        case .divider:
            Divider()
        }
    }

    private func codeBlock(language: String?, content: String) -> some View {
        let bounded = AgentCodeBlockPolicy.displayedContent(content)
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language?.uppercased() ?? "CODE")
                    .atelierFont(
                        size: AtelierTypography.micro,
                        weight: .semibold,
                        design: .monospaced
                    )
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    copyToPasteboard(AgentCodeBlockPolicy.copiedContent(content))
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(AtelierGhostButtonStyle())
                .accessibilityLabel("Copy code")
            }
            .padding(.horizontal, AtelierMetrics.spaceS)
            .frame(height: AtelierMetrics.fieldHeight)
            .background(AtelierTheme.raised)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(bounded)
                    .atelierFont(size: AtelierTypography.label, design: .monospaced)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(AtelierMetrics.spaceS)
            }
            .atelierScrollChrome(backgroundColor: AppKitThemeAdapter.panel)
        }
        .atelierCard()
    }

    @ViewBuilder
    private func table(headers: [String], rows: [[String]]) -> some View {
        if headers.count <= 3 {
            tableGrid(headers: headers, rows: rows, isFlexible: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ScrollView(.horizontal, showsIndicators: true) {
                tableGrid(headers: headers, rows: rows, isFlexible: false)
            }
            .atelierScrollChrome(backgroundColor: AppKitThemeAdapter.panel)
        }
    }

    private func tableGrid(
        headers: [String],
        rows: [[String]],
        isFlexible: Bool
    ) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                ForEach(headers.indices, id: \.self) { index in
                    tableCell(headers[index], isHeader: true, isFlexible: isFlexible)
                }
            }
            ForEach(rows.indices, id: \.self) { rowIndex in
                Divider()
                    .gridCellColumns(headers.count)
                GridRow {
                    ForEach(headers.indices, id: \.self) { columnIndex in
                        let value = rows[rowIndex].indices.contains(columnIndex)
                            ? rows[rowIndex][columnIndex]
                            : ""
                        tableCell(value, isHeader: false, isFlexible: isFlexible)
                    }
                }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: AtelierTheme.controlRadius)
                .stroke(AtelierTheme.border, lineWidth: AtelierTheme.strokeControl)
        }
        .clipShape(RoundedRectangle(cornerRadius: AtelierTheme.controlRadius))
    }

    private func tableCell(
        _ value: String,
        isHeader: Bool,
        isFlexible: Bool
    ) -> some View {
        inlineText(value)
            .atelierFont(
                size: AtelierTypography.label,
                weight: isHeader ? .semibold : .regular
            )
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, AtelierMetrics.spaceM)
            .padding(.vertical, AtelierMetrics.spaceS)
            .frame(
                minWidth: isFlexible ? 0 : 112,
                maxWidth: isFlexible ? .infinity : 240,
                alignment: .leading
            )
            .background(isHeader ? AtelierTheme.raised : Color.clear)
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func listRow(marker: String, content: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AtelierMetrics.spaceS) {
            Text(marker)
                .atelierFont(size: AtelierTypography.body, design: .monospaced)
                .foregroundStyle(.secondary)
                .frame(minWidth: AtelierMetrics.spaceL, alignment: .trailing)
            inlineText(content)
                .atelierFont(size: AtelierTypography.body)
                .lineSpacing(AtelierMetrics.spaceXS)
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
        case 1: AtelierTypography.display
        case 2: AtelierTypography.headline
        case 3: AtelierTypography.uiSize
        default: AtelierTypography.body
        }
    }
}

struct MermaidResponseCard: View {
    let source: String
    let parseError: String?

    @State private var image: NSImage?
    @State private var imageSource: String?
    @State private var renderError: String?
    @State private var showsSource = false
    @State private var containerWidth: CGFloat = 480
    @State private var isRendering = false

    init(source: String, parseError: String? = nil) {
        self.source = source
        self.parseError = parseError
    }

    private var renderWidth: CGFloat {
        MermaidRenderingPolicy.widthBucket(containerWidth: containerWidth)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AtelierMetrics.spaceS) {
            HStack(spacing: AtelierMetrics.spaceS) {
                Label("Mermaid", systemImage: "point.3.connected.trianglepath.dotted")
                    .atelierFont(
                        size: AtelierTypography.caption,
                        weight: .semibold,
                        design: .monospaced
                    )
                    .foregroundStyle(AtelierTheme.accent)
                Spacer()
                Button(showsSource ? "Hide source" : "View source") {
                    showsSource.toggle()
                }
                .buttonStyle(AtelierGhostButtonStyle())
                .accessibilityLabel(showsSource ? "Hide Mermaid source" : "View Mermaid source")
            }

            switch MermaidResponsePresentationPolicy.displayState(
                hasImage: image != nil,
                error: parseError ?? renderError
            ) {
            case .rendered:
                if let image {
                    ZStack(alignment: .topTrailing) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if isRendering {
                            ProgressView()
                                .controlSize(.small)
                                .padding(AtelierMetrics.spaceS)
                                .background(.regularMaterial)
                                .clipShape(Circle())
                        }
                    }
                }
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .atelierFont(size: AtelierTypography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .loading:
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }

            if MermaidResponsePresentationPolicy.showsSource(
                userRequested: showsSource,
                hasRenderError: parseError != nil || renderError != nil
            ) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("MERMAID SOURCE")
                            .atelierFont(
                                size: AtelierTypography.micro,
                                weight: .semibold,
                                design: .monospaced
                            )
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(source, forType: .string)
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(AtelierGhostButtonStyle())
                        .accessibilityLabel("Copy Mermaid source")
                    }
                    .padding(.horizontal, AtelierMetrics.spaceS)
                    .frame(height: AtelierMetrics.fieldHeight)
                    .background(AtelierTheme.raised)

                    Text(source)
                        .atelierFont(size: AtelierTypography.label, design: .monospaced)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(AtelierMetrics.spaceM)
                }
                .background(AtelierTheme.editor)
                .clipShape(RoundedRectangle(cornerRadius: AtelierTheme.controlRadius))
            }
        }
        .padding(AtelierMetrics.spaceM)
        .atelierCard()
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear { containerWidth = max(1, geometry.size.width) }
                    .onChange(of: geometry.size.width) { _, width in
                        containerWidth = max(1, width)
                    }
            }
        }
        .task(id: MermaidRenderRequest(
            source: source,
            width: Int(renderWidth),
            parseError: parseError
        )) {
            guard parseError == nil else {
                image = nil
                imageSource = nil
                renderError = nil
                isRendering = false
                return
            }
            do {
                try await Task.sleep(for: .milliseconds(180))
            } catch {
                return
            }
            if imageSource != source {
                image = nil
                imageSource = nil
            }
            renderError = nil
            isRendering = true
            defer { isRendering = false }
            do {
                let rendered = try await MermaidImageCache.shared.image(
                    source: source,
                    width: renderWidth
                )
                guard !Task.isCancelled else { return }
                image = rendered
                imageSource = source
            } catch {
                guard !Task.isCancelled else { return }
                renderError = "Mermaid syntax could not be rendered. Source is shown below."
            }
        }
    }
}

private struct MermaidRenderRequest: Hashable {
    let source: String
    let width: Int
    let parseError: String?
}

nonisolated enum AgentMarkdownBlock: Equatable, Sendable {
    case heading(level: Int, content: String)
    case paragraph(String)
    case unorderedItem(String)
    case orderedItem(number: Int, content: String)
    case quote(String)
    case code(language: String?, content: String)
    case mermaid(String)
    case invalidMermaid(source: String, error: String)
    case table(headers: [String], rows: [[String]])
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

        func flushFence(isClosed: Bool) {
            let content = fencedLines.joined(separator: "\n")
            if fenceLanguage?.lowercased() == "mermaid" {
                if !isClosed {
                    blocks.append(.invalidMermaid(
                        source: content,
                        error: "Mermaid block is missing its closing fence. Source is shown below."
                    ))
                } else if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    blocks.append(.invalidMermaid(
                        source: content,
                        error: "Mermaid block is empty. Source is shown below."
                    ))
                } else {
                    blocks.append(.mermaid(content))
                }
            } else {
                blocks.append(.code(language: fenceLanguage, content: content))
            }
            fencedLines.removeAll(keepingCapacity: true)
            fenceMarker = nil
            fenceLanguage = nil
        }

        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var lineIndex = 0
        while lineIndex < lines.count {
            let line = lines[lineIndex]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let fenceMarker {
                if isFenceClosing(trimmed, marker: fenceMarker) {
                    flushFence(isClosed: true)
                } else {
                    fencedLines.append(line)
                }
                lineIndex += 1
                continue
            }

            if let opening = fenceOpening(trimmed) {
                flushParagraph()
                fenceMarker = opening.marker
                fenceLanguage = opening.language
                lineIndex += 1
                continue
            }

            if lineIndex + 1 < lines.count,
               let headers = tableRow(from: trimmed),
               isTableDivider(lines[lineIndex + 1], columnCount: headers.count) {
                flushParagraph()
                var rows: [[String]] = []
                lineIndex += 2
                while lineIndex < lines.count,
                      let row = tableRow(from: lines[lineIndex]),
                      !isTableDivider(lines[lineIndex], columnCount: headers.count) {
                    rows.append(normalizedTableRow(row, columnCount: headers.count))
                    lineIndex += 1
                }
                blocks.append(.table(headers: headers, rows: rows))
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                lineIndex += 1
                continue
            }

            if isDivider(trimmed) {
                flushParagraph()
                blocks.append(.divider)
                lineIndex += 1
                continue
            }

            if let heading = heading(from: trimmed) {
                flushParagraph()
                blocks.append(.heading(level: heading.level, content: heading.content))
                lineIndex += 1
                continue
            }

            if let content = prefixedContent(in: trimmed, prefixes: ["- ", "* ", "+ "]) {
                flushParagraph()
                blocks.append(.unorderedItem(content))
                lineIndex += 1
                continue
            }

            if let item = orderedItem(from: trimmed) {
                flushParagraph()
                blocks.append(.orderedItem(number: item.number, content: item.content))
                lineIndex += 1
                continue
            }

            if let content = prefixedContent(in: trimmed, prefixes: ["> "]) {
                flushParagraph()
                blocks.append(.quote(content))
                lineIndex += 1
                continue
            }

            paragraph.append(trimmed)
            lineIndex += 1
        }

        if fenceMarker != nil || !fencedLines.isEmpty {
            flushFence(isClosed: false)
        }
        flushParagraph()
        return blocks
    }

    private static func fenceOpening(_ line: String) -> (marker: String, language: String?)? {
        guard let markerCharacter = line.first, markerCharacter == "`" || markerCharacter == "~" else {
            return nil
        }
        let markerLength = line.prefix(while: { $0 == markerCharacter }).count
        guard markerLength >= 3 else { return nil }
        let marker = String(repeating: markerCharacter, count: markerLength)
        let language = line.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
        return (marker, language.isEmpty ? nil : language)
    }

    private static func isFenceClosing(_ line: String, marker: String) -> Bool {
        guard let markerCharacter = marker.first,
              line.count >= marker.count,
              line.allSatisfy({ $0 == markerCharacter }) else {
            return false
        }
        return true
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

    private static func tableRow(from line: String) -> [String]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else { return nil }
        var cells = trimmed.split(separator: "|", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        if trimmed.hasPrefix("|") { cells.removeFirst() }
        if trimmed.hasSuffix("|") { cells.removeLast() }
        return cells.isEmpty ? nil : cells
    }

    private static func isTableDivider(_ line: String, columnCount: Int) -> Bool {
        guard let cells = tableRow(from: line), cells.count == columnCount else { return false }
        return cells.allSatisfy { cell in
            let marker = cell.trimmingCharacters(in: .whitespaces)
            let dashes = marker.filter { $0 == "-" }.count
            return dashes >= 3 && marker.allSatisfy { $0 == "-" || $0 == ":" }
        }
    }

    private static func normalizedTableRow(_ row: [String], columnCount: Int) -> [String] {
        var normalized = Array(row.prefix(columnCount))
        if normalized.count < columnCount {
            normalized.append(contentsOf: repeatElement("", count: columnCount - normalized.count))
        }
        return normalized
    }
}
