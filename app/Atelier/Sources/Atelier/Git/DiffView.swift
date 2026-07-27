import Observation
import SwiftUI
import UniformTypeIdentifiers

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

        self.lines = parsedLines.filter { $0.kind != .metadata }
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
    case image(Data)
    case message(String)
    case failed(String)
}

private nonisolated struct GitImagePreviewError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

private nonisolated enum GitImagePreviewLoader {
    static func supports(path: String) -> Bool {
        let fileExtension = URL(fileURLWithPath: path).pathExtension
        return UTType(filenameExtension: fileExtension)?.conforms(to: .image) == true
    }

    static func load(
        selection: DiffSelection,
        workspacePath: String,
        service: GitService
    ) async throws -> Data {
        if selection.staged {
            let limit = FileLoader.defaultImageLimit
            let data = try await service.run(
                arguments: ["cat-file", "blob", ":\(selection.change.path)"],
                workspacePath: workspacePath,
                maxOutputBytes: limit
            )
            guard data.count <= limit else {
                throw GitImagePreviewError(
                    message: "Image is too large to preview."
                )
            }
            return data
        }

        let fileURL = URL(fileURLWithPath: workspacePath, isDirectory: true)
            .appendingPathComponent(selection.change.path)
        let content = await FileLoader.loadAsync(url: fileURL)
        guard case .image(let data) = content else {
            throw GitImagePreviewError(message: content.displayText)
        }
        return data
    }
}

/// Shared LRU cache of raw `git diff` output, keyed by the diff request plus a
/// revision that bumps whenever the repository changes. Reselecting a file in
/// the Changes panel then serves from memory instead of respawning `git diff`.
/// Bounded by entry count and total bytes so large diffs cannot grow unbounded.
@MainActor
final class GitDiffCache {
    struct Key: Hashable {
        let path: String
        let originalPath: String?
        let staged: Bool
        let isUntracked: Bool
        let revision: Int
    }

    private(set) var revision = 0
    private var entries: [Key: String] = [:]
    private var order: [Key] = []
    private var totalBytes = 0
    private let maximumEntries = 24
    private let maximumBytes = 16 * 1024 * 1024

    func value(for key: Key) -> String? {
        guard let value = entries[key] else { return nil }
        if let index = order.firstIndex(of: key) {
            order.remove(at: index)
            order.append(key)
        }
        return value
    }

    func store(_ value: String, for key: Key) {
        let byteCount = value.utf8.count
        guard byteCount <= maximumBytes else { return }
        if let existing = entries[key] {
            totalBytes -= existing.utf8.count
            if let index = order.firstIndex(of: key) { order.remove(at: index) }
        }
        entries[key] = value
        order.append(key)
        totalBytes += byteCount
        while entries.count > maximumEntries || totalBytes > maximumBytes {
            guard let oldest = order.first else { break }
            order.removeFirst()
            if let removed = entries.removeValue(forKey: oldest) {
                totalBytes -= removed.utf8.count
            }
        }
    }

    /// The repository changed. Bump the revision so an in-flight load stores its
    /// result under the now-stale key and later lookups miss, then drop entries.
    func invalidateAll() {
        revision &+= 1
        entries.removeAll(keepingCapacity: true)
        order.removeAll(keepingCapacity: true)
        totalBytes = 0
    }
}

@MainActor
@Observable
final class GitDiffSession {
    let selection: DiffSelection
    let workspacePath: String
    private(set) var state: GitDiffLoadState = .loading
    private(set) var needsReload = false

    private let service: GitService
    private let cache: GitDiffCache
    private var loadTask: Task<Void, Never>?
    private var loadGeneration = 0

    init(
        selection: DiffSelection,
        workspacePath: String,
        service: GitService = GitService(),
        cache: GitDiffCache = GitDiffCache()
    ) {
        self.selection = selection
        self.workspacePath = workspacePath
        self.service = service
        self.cache = cache
        reload()
    }

    func reload() {
        loadGeneration &+= 1
        let generation = loadGeneration
        loadTask?.cancel()
        needsReload = false

        if GitImagePreviewLoader.supports(path: selection.change.path) {
            state = .loading
            loadTask = Task { [weak self] in
                guard let self else { return }
                do {
                    let data = try await GitImagePreviewLoader.load(
                        selection: selection,
                        workspacePath: workspacePath,
                        service: service
                    )
                    guard !Task.isCancelled, loadGeneration == generation else { return }
                    state = .image(data)
                } catch is CancellationError {
                    return
                } catch {
                    guard !Task.isCancelled, loadGeneration == generation else { return }
                    state = .failed(error.localizedDescription)
                    AppLogger.git.error(
                        "Git image preview failed: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
            return
        }

        let isUntracked = selection.change.kind == .untracked
        let key = GitDiffCache.Key(
            path: selection.change.path,
            originalPath: selection.change.originalPath,
            staged: selection.staged,
            isUntracked: isUntracked,
            revision: cache.revision
        )

        if let cached = cache.value(for: key) {
            state = cached.isEmpty
                ? .message("No diff output for this file.")
                : .loaded(GitDiffDocument(text: cached))
            return
        }

        state = .loading
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let output: String
                if isUntracked {
                    output = try await service.untrackedDiff(
                        path: selection.change.path,
                        workspacePath: workspacePath
                    )
                } else {
                    output = try await service.diff(
                        path: selection.change.path,
                        originalPath: selection.change.originalPath,
                        staged: selection.staged,
                        workspacePath: workspacePath
                    )
                }
                guard !Task.isCancelled, loadGeneration == generation else { return }
                cache.store(output, for: key)
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
        HStack(spacing: AtelierMetrics.spaceS) {
            Image(
                systemName: GitImagePreviewLoader.supports(path: session.selection.change.path)
                    ? "photo"
                    : "doc.text.magnifyingglass"
            )
                .foregroundStyle(AtelierTheme.accent)

            VStack(alignment: .leading, spacing: AtelierMetrics.spaceXS) {
                Text(session.selection.change.path)
                    .atelierFont(size: AtelierTypography.uiSize, weight: .medium)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let originalPath = session.selection.change.originalPath {
                    Text("Renamed from \(originalPath)")
                        .atelierFont(size: AtelierTypography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Text(session.selection.stateLabel)
                .atelierFont(size: AtelierTypography.micro, weight: .semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, AtelierMetrics.spaceS)
                .padding(.vertical, AtelierMetrics.spaceXS)
                .background(AtelierTheme.raised)
                .clipShape(
                    RoundedRectangle(cornerRadius: AtelierTheme.rowRadius, style: .continuous)
                )

            Spacer(minLength: AtelierMetrics.spaceS)

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
        .padding(.horizontal, AtelierMetrics.spaceM)
        .frame(height: AtelierMetrics.panelHeaderHeight)
        .background(AtelierTheme.chrome)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AtelierTheme.border)
                .frame(height: AtelierTheme.strokeHairline)
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
        case .image(let data):
            ImageViewer(data: data, name: session.selection.displayName)
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
                .buttonStyle(AtelierLuminarePrimaryButtonStyle())
            }
        }
    }

    private func changeCount(_ text: String, color: Color) -> some View {
        Text(text)
            .atelierFont(size: AtelierTypography.label, weight: .semibold, design: .monospaced)
            .foregroundStyle(color)
            .accessibilityLabel(text.first == "+" ? "\(text.dropFirst()) additions" : "\(text.dropFirst()) deletions")
    }

    private func diffStateView<Accessory: View>(
        title: String,
        message: String,
        systemImage: String,
        @ViewBuilder accessory: @escaping () -> Accessory
    ) -> some View {
        AtelierEmptyState(
            systemImage: systemImage,
            title: title,
            message: message,
            accessory: accessory
        )
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
                .frame(
                    minWidth: geometry.size.width,
                    minHeight: geometry.size.height,
                    alignment: .topLeading
                )
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
                .atelierFont(
                    size: AtelierTypography.body,
                    weight: .semibold,
                    design: .monospaced
                )
                .foregroundStyle(markerColor)
                .frame(width: AtelierMetrics.compactControlHeight)
                .accessibilityHidden(true)

            Text(line.text.isEmpty ? " " : line.text)
                .atelierFont(
                    size: AtelierTypography.body,
                    weight: line.kind == .hunk ? .semibold : .regular,
                    design: .monospaced
                )
                .foregroundStyle(textColor)
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.trailing, AtelierMetrics.spaceL)
        }
        .frame(
            minWidth: 0,
            maxWidth: .infinity,
            minHeight: AtelierMetrics.compactControlHeight * scale,
            alignment: .leading
        )
        .background(backgroundColor)
        .overlay(alignment: .bottom) {
            if line.kind == .hunk {
                Rectangle()
                    .fill(AtelierTheme.border.opacity(0.65))
                    .frame(height: AtelierTheme.strokeHairline)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private func lineNumber(_ number: Int?, label: String) -> some View {
        Text(number.map(String.init) ?? "")
            .atelierFont(size: AtelierTypography.label, design: .monospaced)
            .foregroundStyle(.secondary)
            .frame(
                width: AtelierMetrics.codeGutterWidth,
                height: AtelierMetrics.compactControlHeight * scale,
                alignment: .trailing
            )
            .padding(.trailing, AtelierMetrics.spaceS)
            .background(AtelierTheme.chrome.opacity(0.55))
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(AtelierTheme.border)
                    .frame(width: AtelierTheme.strokeHairline)
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
