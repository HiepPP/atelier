import Observation
import SwiftUI

nonisolated enum GitDiffLineKind: Equatable, Sendable {
    case metadata
    case hunk
    case addition
    case deletion
    case context
    case note
}

nonisolated struct GitDiffLine: Identifiable, Equatable, Sendable {
    let id: Int
    let kind: GitDiffLineKind
    let oldLineNumber: Int?
    let newLineNumber: Int?
    let text: String

    var marker: String {
        switch kind {
        case .addition: "+"
        case .deletion: "-"
        case .context: " "
        case .metadata, .hunk, .note: ""
        }
    }
}

nonisolated struct GitDiffDocument: Equatable, Sendable {
    let lines: [GitDiffLine]
    let additions: Int
    let deletions: Int

    init(text: String) {
        var parsedLines: [GitDiffLine] = []
        var additions = 0
        var deletions = 0
        var oldLineNumber: Int?
        var newLineNumber: Int?
        var isInsideHunk = false
        var rawLines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if text.hasSuffix("\n"), rawLines.last?.isEmpty == true {
            rawLines.removeLast()
        }

        for (index, rawLine) in rawLines.enumerated() {
            let kind: GitDiffLineKind
            let displayedText: String
            let displayedOldLine: Int?
            let displayedNewLine: Int?

            if rawLine.hasPrefix("diff --git ") {
                isInsideHunk = false
                oldLineNumber = nil
                newLineNumber = nil
                kind = .metadata
                displayedText = rawLine
                displayedOldLine = nil
                displayedNewLine = nil
            } else if let hunkStart = Self.hunkStart(in: rawLine) {
                isInsideHunk = true
                oldLineNumber = hunkStart.old
                newLineNumber = hunkStart.new
                kind = .hunk
                displayedText = rawLine
                displayedOldLine = nil
                displayedNewLine = nil
            } else if isInsideHunk, rawLine.hasPrefix("+") {
                kind = .addition
                displayedText = String(rawLine.dropFirst())
                displayedOldLine = nil
                displayedNewLine = newLineNumber
                newLineNumber = newLineNumber.map { $0 + 1 }
                additions += 1
            } else if isInsideHunk, rawLine.hasPrefix("-") {
                kind = .deletion
                displayedText = String(rawLine.dropFirst())
                displayedOldLine = oldLineNumber
                displayedNewLine = nil
                oldLineNumber = oldLineNumber.map { $0 + 1 }
                deletions += 1
            } else if isInsideHunk, rawLine.hasPrefix(" ") {
                kind = .context
                displayedText = String(rawLine.dropFirst())
                displayedOldLine = oldLineNumber
                displayedNewLine = newLineNumber
                oldLineNumber = oldLineNumber.map { $0 + 1 }
                newLineNumber = newLineNumber.map { $0 + 1 }
            } else if rawLine.hasPrefix("\\ No newline at end of file") {
                kind = .note
                displayedText = rawLine
                displayedOldLine = nil
                displayedNewLine = nil
            } else {
                kind = .metadata
                displayedText = rawLine
                displayedOldLine = nil
                displayedNewLine = nil
            }

            parsedLines.append(GitDiffLine(
                id: index,
                kind: kind,
                oldLineNumber: displayedOldLine,
                newLineNumber: displayedNewLine,
                text: displayedText
            ))
        }

        self.lines = parsedLines
        self.additions = additions
        self.deletions = deletions
    }

    private static func hunkStart(in line: String) -> (old: Int, new: Int)? {
        let fields = line.split(separator: " ")
        guard fields.count >= 3,
              fields[0] == "@@",
              let old = lineStart(in: fields[1], prefix: "-"),
              let new = lineStart(in: fields[2], prefix: "+") else {
            return nil
        }
        return (old, new)
    }

    private static func lineStart(in field: Substring, prefix: Character) -> Int? {
        guard field.first == prefix else { return nil }
        guard let start = field.dropFirst().split(separator: ",", maxSplits: 1).first else {
            return nil
        }
        return Int(start)
    }
}

nonisolated enum GitDiffLoadState: Equatable, Sendable {
    case loading
    case loaded(GitDiffDocument)
    case message(String)
    case failed(String)
}

@MainActor
@Observable
final class GitDiffSession {
    let selection: DiffSelection
    let workspacePath: String
    private(set) var state: GitDiffLoadState = .loading
    private(set) var needsReload = false

    private let service: GitService
    private var loadTask: Task<Void, Never>?
    private var loadGeneration = 0

    init(
        selection: DiffSelection,
        workspacePath: String,
        service: GitService = GitService()
    ) {
        self.selection = selection
        self.workspacePath = workspacePath
        self.service = service
        reload()
    }

    func reload() {
        loadGeneration &+= 1
        let generation = loadGeneration
        loadTask?.cancel()
        needsReload = false

        guard selection.change.kind != .untracked else {
            state = .message("Untracked file. Stage it to view a unified diff.")
            return
        }

        state = .loading
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let output = try await service.diff(
                    path: selection.change.path,
                    originalPath: selection.change.originalPath,
                    staged: selection.staged,
                    workspacePath: workspacePath
                )
                guard !Task.isCancelled, loadGeneration == generation else { return }
                state = output.isEmpty
                    ? .message("No diff output for this file.")
                    : .loaded(GitDiffDocument(text: output))
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, loadGeneration == generation else { return }
                state = .failed(error.localizedDescription)
                AppLogger.git.error("Git diff failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func invalidate() {
        needsReload = true
    }

    func close() {
        loadGeneration &+= 1
        loadTask?.cancel()
        loadTask = nil
    }

    isolated deinit {
        close()
    }
}

struct GitDiffTabView: View {
    let session: GitDiffSession
    @Environment(AtelierZoomModel.self) private var zoom

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .background(AtelierTheme.editor)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .foregroundStyle(AtelierTheme.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.selection.change.path)
                    .atelierFont(size: AtelierTypography.uiSize, weight: .medium)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let originalPath = session.selection.change.originalPath {
                    Text("Renamed from \(originalPath)")
                        .atelierFont(size: 10.5)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Text(session.selection.stateLabel.uppercased())
                .atelierFont(size: 9.5, weight: .semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(AtelierTheme.raised)
                .clipShape(Capsule())

            Spacer(minLength: 8)

            if case .loaded(let document) = session.state {
                changeCount("+\(document.additions)", color: AtelierTheme.gitAdded)
                changeCount("-\(document.deletions)", color: AtelierTheme.gitDeleted)
            }

            Button {
                session.reload()
            } label: {
                Image(systemName: session.needsReload ? "arrow.clockwise.circle.fill" : "arrow.clockwise")
            }
            .buttonStyle(AtelierLuminareIconButtonStyle())
            .foregroundStyle(session.needsReload ? AtelierTheme.accent : Color.secondary)
            .help(session.needsReload ? "Reload changed diff" : "Reload diff")
            .accessibilityLabel(session.needsReload ? "Reload changed diff" : "Reload diff")
        }
        .padding(.horizontal, 12)
        .frame(height: 46)
        .background(AtelierTheme.chrome)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AtelierTheme.border)
                .frame(height: 0.5)
        }
        .environment(\.atelierZoomScale, zoom.contentScale)
    }

    @ViewBuilder
    private var content: some View {
        switch session.state {
        case .loading:
            diffStateView(
                title: "Loading Diff",
                message: session.selection.change.path,
                systemImage: "arrow.triangle.2.circlepath"
            ) {
                ProgressView()
                    .controlSize(.small)
            }
        case .loaded(let document):
            DiffView(document: document)
                .environment(\.atelierZoomScale, zoom.contentScale)
        case .message(let message):
            diffStateView(
                title: "No Diff Available",
                message: message,
                systemImage: "doc.text.magnifyingglass"
            )
        case .failed(let message):
            diffStateView(
                title: "Could Not Load Diff",
                message: message,
                systemImage: "exclamationmark.triangle"
            ) {
                Button("Try Again") {
                    session.reload()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func changeCount(_ text: String, color: Color) -> some View {
        Text(text)
            .atelierFont(size: 11, weight: .semibold, design: .monospaced)
            .foregroundStyle(color)
            .accessibilityLabel(text.first == "+" ? "\(text.dropFirst()) additions" : "\(text.dropFirst()) deletions")
    }

    private func diffStateView<Accessory: View>(
        title: String,
        message: String,
        systemImage: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .atelierFont(size: 30, weight: .ultraLight)
                .foregroundStyle(AtelierTheme.accent)
            Text(title)
                .atelierFont(size: 16, weight: .semibold)
            Text(message)
                .atelierFont(size: AtelierTypography.uiSize)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
            accessory()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.atelierZoomScale, zoom.contentScale)
    }

    private func diffStateView(
        title: String,
        message: String,
        systemImage: String
    ) -> some View {
        diffStateView(title: title, message: message, systemImage: systemImage) {
            EmptyView()
        }
    }
}

struct DiffView: View {
    let document: GitDiffDocument
    @Environment(\.atelierZoomScale) private var scale
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(document.lines) { line in
                        DiffLineView(line: line, colorScheme: colorScheme)
                    }
                }
                .frame(minWidth: geometry.size.width, alignment: .leading)
            }
            .atelierScrollChrome(backgroundColor: AppKitThemeAdapter.code)
        }
        .background(AtelierTheme.code)
        .environment(\.atelierZoomScale, scale)
    }
}

private struct DiffLineView: View {
    let line: GitDiffLine
    let colorScheme: ColorScheme
    @Environment(\.atelierZoomScale) private var scale

    var body: some View {
        HStack(spacing: 0) {
            lineNumber(line.oldLineNumber, label: "Old line")
            lineNumber(line.newLineNumber, label: "New line")

            Text(line.marker)
                .atelierFont(size: 12.5, weight: .semibold, design: .monospaced)
                .foregroundStyle(markerColor)
                .frame(width: 24)
                .accessibilityHidden(true)

            Text(line.text.isEmpty ? " " : line.text)
                .atelierFont(
                    size: 12.5,
                    weight: line.kind == .hunk ? .semibold : .regular,
                    design: .monospaced
                )
                .foregroundStyle(textColor)
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.trailing, 18)
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 22 * scale, alignment: .leading)
        .background(backgroundColor)
        .overlay(alignment: .bottom) {
            if line.kind == .hunk {
                Rectangle()
                    .fill(AtelierTheme.border.opacity(0.65))
                    .frame(height: 0.5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private func lineNumber(_ number: Int?, label: String) -> some View {
        Text(number.map(String.init) ?? "")
            .atelierFont(size: 11, design: .monospaced)
            .foregroundStyle(.secondary)
            .frame(width: 46, height: 22 * scale, alignment: .trailing)
            .padding(.trailing, 8)
            .background(AtelierTheme.chrome.opacity(0.55))
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(AtelierTheme.border)
                    .frame(width: 0.5)
            }
            .accessibilityLabel(label)
            .accessibilityValue(number.map(String.init) ?? "None")
    }

    private var backgroundColor: Color {
        let opacity = colorScheme == .dark ? 0.22 : 0.12
        return switch line.kind {
        case .addition: AtelierTheme.gitAdded.opacity(opacity)
        case .deletion: AtelierTheme.gitDeleted.opacity(opacity)
        case .hunk: AtelierTheme.accent.opacity(colorScheme == .dark ? 0.2 : 0.1)
        case .metadata: AtelierTheme.chrome.opacity(0.35)
        case .context, .note: Color.clear
        }
    }

    private var markerColor: Color {
        switch line.kind {
        case .addition: AtelierTheme.gitAdded
        case .deletion: AtelierTheme.gitDeleted
        case .hunk, .metadata, .context, .note: Color.secondary
        }
    }

    private var textColor: Color {
        switch line.kind {
        case .hunk: AtelierTheme.accent
        case .metadata, .note: Color.secondary
        case .addition, .deletion, .context: Color.primary
        }
    }

    private var accessibilityLabel: String {
        let location: String
        switch (line.oldLineNumber, line.newLineNumber) {
        case let (old?, new?): location = "old line \(old), new line \(new)"
        case let (old?, nil): location = "old line \(old)"
        case let (nil, new?): location = "new line \(new)"
        case (nil, nil): location = ""
        }

        let action: String
        switch line.kind {
        case .addition: action = "Added"
        case .deletion: action = "Deleted"
        case .context: action = "Context"
        case .hunk: action = "Hunk"
        case .metadata: action = "Metadata"
        case .note: action = "Note"
        }
        return [action, location, line.text].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
