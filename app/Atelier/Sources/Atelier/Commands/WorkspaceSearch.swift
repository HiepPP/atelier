import Foundation
import Observation

nonisolated struct WorkspaceSearchQuery: Equatable, Sendable {
    let text: String
    let isCaseSensitive: Bool
    let matchesWholeWords: Bool
    let includesIgnoredFiles: Bool
}

nonisolated struct WorkspaceSearchMatch: Identifiable, Equatable, Sendable {
    let candidate: AtelierFileCandidate
    let lineNumber: Int
    let leadingText: String
    let matchedText: String
    let trailingText: String
    let matchCount: Int

    var id: String { "\(candidate.id):\(lineNumber)" }
}

nonisolated struct WorkspaceSearchFileGroup: Identifiable, Equatable, Sendable {
    let candidate: AtelierFileCandidate
    var matches: [WorkspaceSearchMatch]

    var id: String { candidate.id }
}

nonisolated struct WorkspaceSearchSummary: Equatable, Sendable {
    let searchedFileCount: Int
    let matchedFileCount: Int
    let matchCount: Int
    let isTruncated: Bool
}

nonisolated protocol WorkspaceContentSearching: Sendable {
    func search(
        query: WorkspaceSearchQuery,
        revision: Int,
        ignoredPaths: Set<String>,
        onBatch: @escaping @MainActor @Sendable ([WorkspaceSearchMatch]) -> Void
    ) async throws -> WorkspaceSearchSummary
}

actor WorkspaceSearchService: WorkspaceContentSearching {
    static let maximumResultLines = 1_000
    static let maximumFileBytes = FileLoader.defaultLimit

    private static let batchSize = 40
    private static let excerptLeadingCharacters = 120
    private static let excerptTrailingCharacters = 280

    private let fileIndex: any WorkspaceFileIndexing

    init(fileIndex: any WorkspaceFileIndexing) {
        self.fileIndex = fileIndex
    }

    func search(
        query: WorkspaceSearchQuery,
        revision: Int,
        ignoredPaths: Set<String>,
        onBatch: @escaping @MainActor @Sendable ([WorkspaceSearchMatch]) -> Void
    ) async throws -> WorkspaceSearchSummary {
        let candidates = try await fileIndex.candidates(revision: revision)
        let normalizedIgnoredPaths = FileTreeGitIgnorePresentation.normalized(ignoredPaths)
        return try await Self.scan(
            candidates: candidates,
            query: query,
            ignoredPaths: normalizedIgnoredPaths,
            onBatch: onBatch
        )
    }

    private nonisolated static func scan(
        candidates: [AtelierFileCandidate],
        query: WorkspaceSearchQuery,
        ignoredPaths: Set<String>,
        onBatch: @escaping @MainActor @Sendable ([WorkspaceSearchMatch]) -> Void
    ) async throws -> WorkspaceSearchSummary {
        var batch: [WorkspaceSearchMatch] = []
        var searchedFileCount = 0
        var matchedFileCount = 0
        var matchCount = 0
        var resultLineCount = 0

        for candidate in candidates {
            try Task.checkCancellation()
            if !query.includesIgnoredFiles,
               isIgnored(candidate.relativePath, ignoredPaths: ignoredPaths) {
                continue
            }

            let values = try? candidate.url.resourceValues(forKeys: [.fileSizeKey])
            guard let fileSize = values?.fileSize,
                  fileSize <= maximumFileBytes,
                  let data = try? Data(contentsOf: candidate.url, options: [.mappedIfSafe]),
                  !data.prefix(8_192).contains(0),
                  let text = String(data: data, encoding: .utf8) else {
                continue
            }

            searchedFileCount += 1
            var fileHasMatches = false
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            for (lineIndex, substring) in lines.enumerated() {
                try Task.checkCancellation()
                let line = String(substring)
                guard let lineMatches = lineMatches(in: line, query: query) else { continue }

                fileHasMatches = true
                matchCount += lineMatches.count
                resultLineCount += 1
                let excerpt = excerpt(line: line, matchRange: lineMatches.firstRange)
                batch.append(
                    WorkspaceSearchMatch(
                        candidate: candidate,
                        lineNumber: lineIndex + 1,
                        leadingText: excerpt.leading,
                        matchedText: excerpt.match,
                        trailingText: excerpt.trailing,
                        matchCount: lineMatches.count
                    )
                )

                if batch.count == batchSize {
                    await onBatch(batch)
                    batch.removeAll(keepingCapacity: true)
                    await Task.yield()
                }

                if resultLineCount == maximumResultLines {
                    if !batch.isEmpty {
                        await onBatch(batch)
                    }
                    return WorkspaceSearchSummary(
                        searchedFileCount: searchedFileCount,
                        matchedFileCount: matchedFileCount + 1,
                        matchCount: matchCount,
                        isTruncated: true
                    )
                }
            }
            if fileHasMatches {
                matchedFileCount += 1
            }
        }

        if !batch.isEmpty {
            await onBatch(batch)
        }
        return WorkspaceSearchSummary(
            searchedFileCount: searchedFileCount,
            matchedFileCount: matchedFileCount,
            matchCount: matchCount,
            isTruncated: false
        )
    }

    private nonisolated static func lineMatches(
        in line: String,
        query: WorkspaceSearchQuery
    ) -> (firstRange: Range<String.Index>, count: Int)? {
        let options: String.CompareOptions = query.isCaseSensitive ? [] : [.caseInsensitive]
        var firstRange: Range<String.Index>?
        var count = 0
        var searchStart = line.startIndex

        while searchStart < line.endIndex,
              let range = line.range(
                  of: query.text,
                  options: options,
                  range: searchStart..<line.endIndex
              ) {
            if !query.matchesWholeWords || isWholeWord(range, in: line) {
                firstRange = firstRange ?? range
                count += 1
            }
            searchStart = range.upperBound
        }
        guard let firstRange else { return nil }
        return (firstRange, count)
    }

    private nonisolated static func isWholeWord(
        _ range: Range<String.Index>,
        in line: String
    ) -> Bool {
        let startsAtBoundary = range.lowerBound == line.startIndex
            || !isWordCharacter(line[line.index(before: range.lowerBound)])
        let endsAtBoundary = range.upperBound == line.endIndex
            || !isWordCharacter(line[range.upperBound])
        return startsAtBoundary && endsAtBoundary
    }

    private nonisolated static func isWordCharacter(_ character: Character) -> Bool {
        character == "_" || character.isLetter || character.isNumber
    }

    private nonisolated static func isIgnored(
        _ relativePath: String,
        ignoredPaths: Set<String>
    ) -> Bool {
        if ignoredPaths.contains(relativePath) { return true }
        return ignoredPaths.contains { relativePath.hasPrefix($0 + "/") }
    }

    private nonisolated static func excerpt(
        line: String,
        matchRange: Range<String.Index>
    ) -> (leading: String, match: String, trailing: String) {
        let excerptStart = line.index(
            matchRange.lowerBound,
            offsetBy: -excerptLeadingCharacters,
            limitedBy: line.startIndex
        ) ?? line.startIndex
        let excerptEnd = line.index(
            matchRange.upperBound,
            offsetBy: excerptTrailingCharacters,
            limitedBy: line.endIndex
        ) ?? line.endIndex
        let prefix = excerptStart == line.startIndex ? "" : "..."
        let suffix = excerptEnd == line.endIndex ? "" : "..."
        return (
            prefix + line[excerptStart..<matchRange.lowerBound],
            String(line[matchRange]),
            line[matchRange.upperBound..<excerptEnd] + suffix
        )
    }
}

@MainActor
@Observable
final class WorkspaceSearchModel {
    private(set) var query = ""
    private(set) var isCaseSensitive = false
    private(set) var matchesWholeWords = false
    private(set) var includesIgnoredFiles = false
    private(set) var groups: [WorkspaceSearchFileGroup] = []
    private(set) var selectedID: String?
    private(set) var isSearching = false
    private(set) var isWaitingToSearch = false
    private(set) var isPresented = false
    private(set) var searchedFileCount = 0
    private(set) var matchedFileCount = 0
    private(set) var matchCount = 0
    private(set) var isTruncated = false
    private(set) var errorMessage: String?

    private let searcher: any WorkspaceContentSearching
    private let ignoredPaths: @MainActor () -> Set<String>
    private let debounceDuration: Duration
    private var fileRevision = 0
    private var activeRevision: Int?
    private var activeQuery: WorkspaceSearchQuery?
    private var searchGeneration = 0
    private var debounceTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?

    init(
        searcher: any WorkspaceContentSearching,
        ignoredPaths: @escaping @MainActor () -> Set<String> = { [] },
        debounceDuration: Duration = .seconds(1)
    ) {
        self.searcher = searcher
        self.ignoredPaths = ignoredPaths
        self.debounceDuration = debounceDuration
    }

    var matches: [WorkspaceSearchMatch] {
        groups.flatMap(\.matches)
    }

    var selection: WorkspaceSearchMatch? {
        guard let selectedID else { return nil }
        return matches.first { $0.id == selectedID }
    }

    var needsSearch: Bool {
        guard let pendingQuery else { return false }
        return pendingQuery != activeQuery || activeRevision != fileRevision
    }

    func present(revision: Int) {
        fileRevision = revision
        isPresented = true
    }

    func updateFileRevision(_ revision: Int) {
        fileRevision = revision
    }

    func updateQuery(_ query: String) {
        guard self.query != query else { return }
        self.query = query
        scheduleSearch()
    }

    func toggleCaseSensitivity() {
        isCaseSensitive.toggle()
        scheduleSearch()
    }

    func toggleWholeWords() {
        matchesWholeWords.toggle()
        scheduleSearch()
    }

    func toggleIncludesIgnoredFiles() {
        includesIgnoredFiles.toggle()
        scheduleSearch()
    }

    func search() {
        cancelDebounce()
        guard let pendingQuery else {
            cancelSearch()
            activeQuery = nil
            activeRevision = nil
            groups = []
            selectedID = nil
            searchedFileCount = 0
            matchedFileCount = 0
            matchCount = 0
            isTruncated = false
            errorMessage = query.isEmpty ? nil : "Search queries are limited to 500 characters."
            return
        }

        searchGeneration &+= 1
        let generation = searchGeneration
        searchTask?.cancel()
        groups = []
        selectedID = nil
        searchedFileCount = 0
        matchedFileCount = 0
        matchCount = 0
        isTruncated = false
        errorMessage = nil
        isSearching = true
        activeQuery = pendingQuery
        activeRevision = fileRevision

        let searcher = searcher
        let revision = fileRevision
        let ignoredPaths = ignoredPaths()
        searchTask = Task { [weak self] in
            do {
                let summary = try await searcher.search(
                    query: pendingQuery,
                    revision: revision,
                    ignoredPaths: ignoredPaths
                ) { [weak self] batch in
                    guard let self,
                          self.searchGeneration == generation,
                          self.isPresented else { return }
                    self.append(batch)
                }
                guard let self, self.searchGeneration == generation else { return }
                self.searchedFileCount = summary.searchedFileCount
                self.matchedFileCount = summary.matchedFileCount
                self.matchCount = summary.matchCount
                self.isTruncated = summary.isTruncated
                self.isSearching = false
                self.searchTask = nil
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.searchGeneration == generation else { return }
                self.activeQuery = nil
                self.activeRevision = nil
                self.isSearching = false
                self.searchTask = nil
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func moveSelection(by offset: Int) {
        let ids = matches.map(\.id)
        guard !ids.isEmpty else {
            selectedID = nil
            return
        }
        let currentIndex = selectedID.flatMap(ids.firstIndex(of:)) ?? 0
        selectedID = ids[min(max(0, currentIndex + offset), ids.count - 1)]
    }

    func select(id: String?) {
        guard let id, matches.contains(where: { $0.id == id }) else { return }
        selectedID = id
    }

    func settleSearch() async {
        await debounceTask?.value
        await searchTask?.value
    }

    func dismiss() {
        if isSearching {
            activeRevision = nil
        }
        cancelDebounce()
        cancelSearch()
        isPresented = false
    }

    func stop() {
        dismiss()
    }

    private var pendingQuery: WorkspaceSearchQuery? {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 500 else { return nil }
        return WorkspaceSearchQuery(
            text: text,
            isCaseSensitive: isCaseSensitive,
            matchesWholeWords: matchesWholeWords,
            includesIgnoredFiles: includesIgnoredFiles
        )
    }

    private func append(_ batch: [WorkspaceSearchMatch]) {
        for match in batch {
            if groups.last?.candidate.id == match.candidate.id {
                groups[groups.count - 1].matches.append(match)
            } else {
                groups.append(
                    WorkspaceSearchFileGroup(candidate: match.candidate, matches: [match])
                )
            }
            if selectedID == nil {
                selectedID = match.id
            }
            matchCount += match.matchCount
        }
        matchedFileCount = groups.count
    }

    private func scheduleSearch() {
        cancelDebounce()
        cancelSearch()
        guard pendingQuery != nil else {
            search()
            return
        }

        isWaitingToSearch = true
        let debounceDuration = debounceDuration
        debounceTask = Task { [weak self] in
            do {
                try await Task.sleep(for: debounceDuration)
                guard let self, !Task.isCancelled else { return }
                self.debounceTask = nil
                self.isWaitingToSearch = false
                self.search()
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }

    private func cancelDebounce() {
        debounceTask?.cancel()
        debounceTask = nil
        isWaitingToSearch = false
    }

    private func cancelSearch() {
        searchGeneration &+= 1
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
    }
}
