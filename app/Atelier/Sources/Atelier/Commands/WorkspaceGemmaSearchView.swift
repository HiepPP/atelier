import Foundation
import SwiftUI

struct WorkspaceGemmaSearchResultsView: View {
    @Bindable var model: WorkspaceGemmaSearchModel
    let onActivate: (WorkspaceGemmaSearchSource) -> Void

    var body: some View {
        if showsEmptyState {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: AtelierMetrics.spaceL) {
                        if !model.answer.isEmpty {
                            answer
                        }
                        if !model.sources.isEmpty {
                            sources
                        }
                        if let errorMessage = model.errorMessage {
                            error(errorMessage)
                        }
                    }
                    .padding(AtelierMetrics.spaceL)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .atelierScrollChrome(backgroundColor: AppKitThemeAdapter.raised)
                .background(AtelierTheme.raised)
                .onChange(of: model.selectedSourceID) {
                    guard let selectedSourceID = model.selectedSourceID else { return }
                    proxy.scrollTo(selectedSourceID, anchor: .center)
                }
            }
        }
    }

    private var showsEmptyState: Bool {
        model.answer.isEmpty && model.sources.isEmpty && model.errorMessage == nil
    }

    private var emptyState: some View {
        AtelierEmptyState(
            systemImage: emptyStateImage,
            title: emptyStateTitle,
            message: emptyStateMessage
        )
    }

    private var answer: some View {
        VStack(alignment: .leading, spacing: AtelierMetrics.spaceS) {
            Text("Gemma")
                .atelierFont(size: AtelierTypography.caption, weight: .semibold)
                .foregroundStyle(AtelierTheme.accent)
            VStack(alignment: .leading, spacing: AtelierMetrics.spaceM) {
                ForEach(WorkspaceGemmaSourceLinkPolicy.answerBlocks(model.answer)) { block in
                    answerBlock(block)
                }
            }
        }
        .frame(maxWidth: AtelierMetrics.transcriptMaxWidth, alignment: .leading)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func answerBlock(_ block: WorkspaceGemmaAnswerBlock) -> some View {
        if let source = block.source, let display = block.sourceDisplay {
            Button {
                guard NSEvent.modifierFlags.contains(.command) else { return }
                onActivate(source)
            } label: {
                Text(display)
                    .atelierFont(size: AtelierTypography.editorSize, design: .monospaced)
                    .foregroundStyle(AtelierTheme.accent)
                    .padding(.horizontal, AtelierMetrics.spaceXS)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(AtelierTheme.accent.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
            .atelierPointerCursor()
            .help("Command-click to open \(source.path), line \(source.lineNumber)")
            .accessibilityLabel("Open \(source.path), line \(source.lineNumber)")
            .accessibilityHint("Command-click to open")
            .accessibilityAction {
                onActivate(source)
            }
        } else {
            AgentMarkdownView(
                source: WorkspaceGemmaSourceLinkPolicy.linkifiedMarkdown(block.markdown),
                bodyFontSize: AtelierTypography.editorSize
            )
                .textSelection(.enabled)
                .environment(\.openURL, OpenURLAction(handler: handleAnswerURL))
        }
    }

    private func handleAnswerURL(_ url: URL) -> OpenURLAction.Result {
        guard NSEvent.modifierFlags.contains(.command),
              let source = WorkspaceGemmaSourceLinkPolicy.source(from: url) else {
            if url.scheme == WorkspaceGemmaSourceLinkPolicy.scheme {
                return .discarded
            }
            return .systemAction
        }
        onActivate(source)
        return .handled
    }

    private var sources: some View {
        VStack(alignment: .leading, spacing: AtelierMetrics.spaceS) {
            HStack {
                Text("Sources")
                    .atelierFont(size: AtelierTypography.label, weight: .semibold)
                Spacer()
                Text("\(model.sources.count)")
                    .atelierFont(size: AtelierTypography.micro, design: .monospaced)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: AtelierMetrics.spaceXS) {
                ForEach(model.sources) { source in
                    Button {
                        model.selectSource(id: source.id)
                        onActivate(source)
                    } label: {
                        sourceRow(source)
                    }
                    .id(source.id)
                    .buttonStyle(.plain)
                    .atelierPointerCursor()
                    .accessibilityLabel(
                        "Open \(source.path), line \(source.lineNumber)"
                    )
                    .accessibilityValue(
                        model.selectedSourceID == source.id ? "Selected" : "Not selected"
                    )
                }
            }
        }
    }

    private func sourceRow(_ source: WorkspaceGemmaSearchSource) -> some View {
        VStack(alignment: .leading, spacing: AtelierMetrics.spaceXS) {
            HStack(spacing: AtelierMetrics.spaceS) {
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(URL(fileURLWithPath: source.path).lastPathComponent)
                    .atelierFont(size: AtelierTypography.caption, weight: .semibold)
                    .lineLimit(1)
                Text("Line \(source.lineNumber)")
                    .atelierFont(size: AtelierTypography.micro, design: .monospaced)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Text(source.path)
                .atelierFont(size: AtelierTypography.micro, design: .monospaced)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            if !source.excerpt.isEmpty {
                Text(source.excerpt)
                    .atelierFont(size: AtelierTypography.editorSize, design: .monospaced)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(AtelierMetrics.spaceS)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            model.selectedSourceID == source.id
                ? AtelierTheme.selection
                : AtelierTheme.panel
        )
        .clipShape(
            RoundedRectangle(cornerRadius: AtelierTheme.rowRadius, style: .continuous)
        )
        .contentShape(
            RoundedRectangle(cornerRadius: AtelierTheme.rowRadius, style: .continuous)
        )
    }

    private func error(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: AtelierMetrics.spaceXS) {
            Text("Gemma could not finish")
                .atelierFont(size: AtelierTypography.label, weight: .semibold)
                .foregroundStyle(AtelierTheme.danger)
            Text(message)
                .atelierFont(size: AtelierTypography.caption)
            if let recoverySuggestion = model.recoverySuggestion {
                Text(recoverySuggestion)
                    .atelierFont(size: AtelierTypography.caption, design: .monospaced)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(AtelierMetrics.spaceS)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AtelierTheme.danger.opacity(0.07))
        .clipShape(
            RoundedRectangle(cornerRadius: AtelierTheme.controlRadius, style: .continuous)
        )
    }

    private var emptyStateImage: String {
        if model.isRunning { return "sparkles" }
        if model.status == .cancelled { return "stop.circle" }
        return "sparkle.magnifyingglass"
    }

    private var emptyStateTitle: String {
        if model.isRunning { return "Gemma is Searching" }
        if model.status == .cancelled { return "Search Stopped" }
        return "Ask Gemma"
    }

    private var emptyStateMessage: String {
        if model.isRunning {
            return "Searching indexed workspace files and reading relevant lines."
        }
        if model.status == .cancelled {
            return "Edit the question or press Return to search again."
        }
        return "Ask where or how something works, then press Return."
    }
}

nonisolated struct WorkspaceGemmaAnswerBlock: Identifiable, Equatable, Sendable {
    let id: Int
    let markdown: String
    let sourceDisplay: String?
    let source: WorkspaceGemmaSearchSource?
}

nonisolated enum WorkspaceGemmaSourceLinkPolicy {
    static let scheme = "atelier-source"

    private static let expression = try? NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9_@+./:-])(`?)((?:/?[A-Za-z0-9_@+.-]+/)+(?:[A-Za-z0-9_@+-]+(?:\.[A-Za-z0-9_@+-]+)+|\.[A-Za-z0-9_@+-]+))(?::([1-9][0-9]*))?\1(?![A-Za-z0-9_@+./:-])"#
    )

    static func answerBlocks(_ source: String) -> [WorkspaceGemmaAnswerBlock] {
        guard !source.isEmpty else { return [] }
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        var blocks: [WorkspaceGemmaAnswerBlock] = []
        var markdown = ""
        var markdownOffset = 0
        var sourceOffset = 0
        var isInFence = false

        func flushMarkdown() {
            let content = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
            if !content.isEmpty {
                blocks.append(
                    WorkspaceGemmaAnswerBlock(
                        id: markdownOffset,
                        markdown: content,
                        sourceDisplay: nil,
                        source: nil
                    )
                )
            }
            markdown = ""
        }

        for (index, lineSlice) in lines.enumerated() {
            let line = String(lineSlice)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isFence = trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")

            if !isInFence, !isFence, let reference = standaloneReference(in: trimmed) {
                flushMarkdown()
                blocks.append(
                    WorkspaceGemmaAnswerBlock(
                        id: sourceOffset,
                        markdown: "",
                        sourceDisplay: reference.display,
                        source: reference.source
                    )
                )
                markdownOffset = sourceOffset + line.utf16.count + 1
            } else {
                if markdown.isEmpty {
                    markdownOffset = sourceOffset
                }
                markdown.append(line)
                if index < lines.count - 1 {
                    markdown.append("\n")
                }
            }

            if isFence {
                isInFence.toggle()
            }
            sourceOffset += line.utf16.count + 1
        }
        flushMarkdown()
        return blocks
    }

    static func linkifiedMarkdown(_ source: String) -> String {
        guard let expression, !source.isEmpty else { return source }
        let fullRange = NSRange(source.startIndex..<source.endIndex, in: source)
        let matches = expression.matches(in: source, range: fullRange)
        guard !matches.isEmpty else { return source }

        var linked = source
        for match in matches.reversed() {
            guard let matchRange = Range(match.range, in: source),
                  let pathRange = Range(match.range(at: 2), in: source) else {
                continue
            }
            if isInsideExistingLink(matchRange, in: source) {
                continue
            }

            let path = String(source[pathRange])
            let lineNumber = Range(match.range(at: 3), in: source)
                .flatMap { Int(source[$0]) } ?? 1
            guard let url = sourceURL(path: path, lineNumber: lineNumber) else {
                continue
            }

            let usesCodeStyle = match.range(at: 1).length > 0
            let display = lineNumber == 1 && match.range(at: 3).location == NSNotFound
                ? path
                : "\(path):\(lineNumber)"
            let label = usesCodeStyle ? "`\(display)`" : display
            linked.replaceSubrange(matchRange, with: "[\(label)](\(url.absoluteString))")
        }
        return linked
    }

    static func source(from url: URL) -> WorkspaceGemmaSearchSource? {
        guard url.scheme == scheme,
              url.host == "open",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let path = components.queryItems?.first(where: { $0.name == "path" })?.value,
              !path.isEmpty else {
            return nil
        }
        let lineNumber = components.queryItems?
            .first(where: { $0.name == "line" })?
            .value
            .flatMap(Int.init) ?? 1
        guard lineNumber > 0 else { return nil }
        return searchSource(path: path, lineNumber: lineNumber)
    }

    private static func sourceURL(path: String, lineNumber: Int) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "open"
        components.queryItems = [
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "line", value: String(lineNumber))
        ]
        return components.url
    }

    private static func isInsideExistingLink(
        _ range: Range<String.Index>,
        in source: String
    ) -> Bool {
        let before = range.lowerBound > source.startIndex
            ? source[source.index(before: range.lowerBound)]
            : nil
        let after = range.upperBound < source.endIndex
            ? source[range.upperBound]
            : nil
        return before == "[" || after == "]"
    }

    private static func standaloneReference(
        in content: String
    ) -> (display: String, source: WorkspaceGemmaSearchSource)? {
        guard let expression else { return nil }
        let fullRange = NSRange(content.startIndex..<content.endIndex, in: content)
        guard let match = expression.firstMatch(in: content, range: fullRange),
              match.range == fullRange,
              let pathRange = Range(match.range(at: 2), in: content) else {
            return nil
        }
        let path = String(content[pathRange])
        let explicitLineRange = Range(match.range(at: 3), in: content)
        let lineNumber = explicitLineRange.flatMap { Int(content[$0]) } ?? 1
        let display = explicitLineRange == nil ? path : "\(path):\(lineNumber)"
        return (display, searchSource(path: path, lineNumber: lineNumber))
    }

    private static func searchSource(
        path: String,
        lineNumber: Int
    ) -> WorkspaceGemmaSearchSource {
        WorkspaceGemmaSearchSource(
            reference: WorkspaceToolReference(
                path: path,
                lineNumber: lineNumber,
                excerpt: ""
            )
        )
    }
}
