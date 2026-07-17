import SwiftUI

struct GemmaAgentView: View {
    @Bindable var model: GemmaAgentModel
    let workspaceRoot: URL
    let onOpenFile: (URL) -> Void

    @FocusState private var isComposerFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            transcript
            Divider()
            composer
        }
        .background(AtelierTheme.editor)
        .onAppear { isComposerFocused = true }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(AtelierTheme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("Gemma Workspace Assistant")
                    .atelierFont(size: 12, weight: .semibold)
                Text("gemma4:cloud - read-only")
                    .atelierFont(size: 9.5, design: .monospaced)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.isRunning {
                ProgressView()
                    .controlSize(.small)
                Button("Stop") { model.stop() }
                    .buttonStyle(.borderless)
                    .help("Stop Gemma")
            } else if !model.messages.isEmpty {
                Button("Clear") { model.clear() }
                    .buttonStyle(.borderless)
                    .help("Clear Gemma session")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(AtelierTheme.chrome)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if model.messages.isEmpty {
                        emptyState
                    }
                    ForEach(model.messages) { message in
                        messageView(message)
                            .id(message.id)
                    }
                    ForEach(model.activities) { activity in
                        toolView(activity)
                            .id(activity.id)
                    }
                    if let error = model.errorMessage {
                        errorView(error, recoverySuggestion: model.recoverySuggestion)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .atelierScrollChrome(backgroundColor: AppKitThemeAdapter.editor)
            .onChange(of: model.messages.last?.content) {
                if let id = model.messages.last?.id {
                    proxy.scrollTo(id, anchor: .bottom)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ask about this workspace")
                .atelierFont(size: 20, weight: .semibold)
            Text("Gemma can search files, read bounded line ranges, and inspect Git diffs. It cannot edit files or run commands.")
                .atelierFont(size: 12)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 520, alignment: .leading)
        .padding(.vertical, 24)
    }

    private func messageView(_ message: GemmaTranscriptMessage) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(message.role == .user ? "YOU" : "GEMMA")
                .atelierFont(size: 9, weight: .bold, design: .monospaced)
                .foregroundStyle(message.role == .user ? AtelierTheme.gitOrange : AtelierTheme.accent)
            if message.content.isEmpty && model.isRunning {
                Text("Thinking...")
                    .italic()
                    .foregroundStyle(.secondary)
            } else if message.role == .assistant {
                GemmaMarkdownView(source: message.content)
                    .textSelection(.enabled)
            } else {
                Text(message.content)
                    .atelierFont(size: 12.5)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(message.role == .user ? AtelierTheme.panel : AtelierTheme.editor)
        .overlay {
            RoundedRectangle(cornerRadius: AtelierTheme.controlRadius)
                .stroke(AtelierTheme.border, lineWidth: 0.75)
        }
        .clipShape(RoundedRectangle(cornerRadius: AtelierTheme.controlRadius))
    }

    private func toolView(_ activity: GemmaToolActivity) -> some View {
        HStack(spacing: 8) {
            Image(systemName: activity.isComplete ? "checkmark.circle" : "ellipsis.circle")
                .foregroundStyle(activity.isComplete ? AtelierTheme.accent : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.name)
                    .atelierFont(size: 9.5, weight: .semibold, design: .monospaced)
                Text(activity.detail)
                    .atelierFont(size: 10.5)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            if let path = activity.referencedFiles.first {
                Button("Open") { open(path) }
                    .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AtelierTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: AtelierTheme.controlRadius))
    }

    private func errorView(_ error: String, recoverySuggestion: String?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Gemma could not finish")
                .atelierFont(size: 11, weight: .semibold)
                .foregroundStyle(.red)
            Text(error)
                .atelierFont(size: 10.5)
            if let recoverySuggestion {
                Text(recoverySuggestion)
                    .atelierFont(size: 10, design: .monospaced)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.06))
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask Gemma about this workspace", text: $model.prompt, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .focused($isComposerFocused)
                .onSubmit(model.send)
                .disabled(model.isRunning)
            Button {
                model.send()
                isComposerFocused = true
            } label: {
                Image(systemName: "arrow.up")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(AtelierLuminareIconButtonStyle())
            .disabled(model.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isRunning)
            .accessibilityLabel("Send to Gemma")
            .help("Send to Gemma")
        }
        .padding(12)
        .background(AtelierTheme.chrome)
    }

    private func open(_ path: String) {
        let url = path.hasPrefix("/")
            ? URL(fileURLWithPath: path)
            : workspaceRoot.appending(path: path)
        let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
        guard resolved.pathComponents.starts(with: workspaceRoot.pathComponents) else { return }
        onOpenFile(resolved)
    }
}

private struct GemmaMarkdownView: View {
    let source: String

    private var blocks: [GemmaMarkdownBlock] {
        GemmaMarkdownBlock.parse(source)
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
    private func blockView(_ block: GemmaMarkdownBlock) -> some View {
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
        case .code(let content):
            let bounded = content.count > 8_000
                ? String(content.prefix(8_000)) + "\n..."
                : content
            Text(bounded)
                .atelierFont(size: 11.5, design: .monospaced)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(AtelierTheme.panel)
                .clipShape(RoundedRectangle(cornerRadius: AtelierTheme.controlRadius))
        case .divider:
            Divider()
        }
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

private enum GemmaMarkdownBlock {
    case heading(level: Int, content: String)
    case paragraph(String)
    case unorderedItem(String)
    case orderedItem(number: Int, content: String)
    case quote(String)
    case code(String)
    case divider

    static func parse(_ source: String) -> [Self] {
        var blocks: [Self] = []
        var paragraph: [String] = []
        var code: [String] = []
        var isInCodeBlock = false

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: " ")))
            paragraph.removeAll(keepingCapacity: true)
        }

        func flushCode() {
            blocks.append(.code(code.joined(separator: "\n")))
            code.removeAll(keepingCapacity: true)
        }

        for line in source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if isInCodeBlock {
                    flushCode()
                } else {
                    flushParagraph()
                }
                isInCodeBlock.toggle()
                continue
            }

            if isInCodeBlock {
                code.append(line)
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

        if isInCodeBlock || !code.isEmpty {
            flushCode()
        }
        flushParagraph()
        return blocks
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
