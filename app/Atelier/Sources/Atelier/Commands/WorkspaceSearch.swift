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
    static let maximumCachedStorageBytes = 64 * 1_024 * 1_024

    private static let batchSize = 40
    private static let excerptLeadingCharacters = 120
    private static let excerptTrailingCharacters = 280

    private struct IndexedDocument {
        let lines: [Substring]
        let storageByteCount: Int

        init(text: String, fileByteCount: Int) {
            lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            storageByteCount = fileByteCount + lines.count * MemoryLayout<Substring>.stride
        }
    }

    private struct IgnoredPathMatcher {
        let exactPaths: Set<String>
        let directoryPrefixes: [String]

        init(paths: Set<String>) {
            exactPaths = paths
            directoryPrefixes = paths.map { $0 + "/" }
        }

        func contains(_ relativePath: String) -> Bool {
            exactPaths.contains(relativePath)
                || directoryPrefixes.contains { relativePath.hasPrefix($0) }
        }
    }

    private let fileIndex: any WorkspaceFileIndexing
    private var cachedRevision: Int?
    private var cachedDocuments: [String: IndexedDocument] = [:]
    private var cachedStorageBytes = 0

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
        prepareCache(for: revision)
        return try await scan(
            candidates: candidates,
            query: query,
            revision: revision,
            ignoredPathMatcher: IgnoredPathMatcher(paths: normalizedIgnoredPaths),
            onBatch: onBatch
        )
    }

    private func scan(
        candidates: [AtelierFileCandidate],
        query: WorkspaceSearchQuery,
        revision: Int,
        ignoredPathMatcher: IgnoredPathMatcher,
        onBatch: @escaping @MainActor @Sendable ([WorkspaceSearchMatch]) -> Void
    ) async throws -> WorkspaceSearchSummary {
        var batch: [WorkspaceSearchMatch] = []
        var searchedFileCount = 0
        var matchedFileCount = 0
        var matchCount = 0
        var resultLineCount = 0
        let comparisonOptions: String.CompareOptions = query.isCaseSensitive
            ? []
            : [.caseInsensitive]

        for candidate in candidates {
            try Task.checkCancellation()
            if !query.includesIgnoredFiles,
               ignoredPathMatcher.contains(candidate.relativePath) {
                continue
            }

            guard let document = document(for: candidate, revision: revision) else {
                continue
            }

            try Task.checkCancellation()
            searchedFileCount += 1
            var fileHasMatches = false
            for (lineIndex, line) in document.lines.enumerated() {
                try Task.checkCancellation()
                guard let lineMatches = Self.lineMatches(
                    in: line,
                    queryText: query.text,
                    comparisonOptions: comparisonOptions,
                    matchesWholeWords: query.matchesWholeWords
                ) else {
                    continue
                }

                fileHasMatches = true
                matchCount += lineMatches.count
                resultLineCount += 1
                let excerpt = Self.excerpt(line: line, matchRange: lineMatches.firstRange)
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

                if batch.count == Self.batchSize {
                    await onBatch(batch)
                    batch.removeAll(keepingCapacity: true)
                    await Task.yield()
                }

                if resultLineCount == Self.maximumResultLines {
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

    private func prepareCache(for revision: Int) {
        guard cachedRevision != revision else { return }
        cachedRevision = revision
        cachedDocuments.removeAll(keepingCapacity: false)
        cachedStorageBytes = 0
    }

    private func document(
        for candidate: AtelierFileCandidate,
        revision: Int
    ) -> IndexedDocument? {
        if cachedRevision == revision,
           let cachedDocument = cachedDocuments[candidate.id] {
            return cachedDocument
        }

        let values = try? candidate.url.resourceValues(forKeys: [.fileSizeKey])
        guard let fileSize = values?.fileSize,
              fileSize <= Self.maximumFileBytes,
              let data = try? Data(contentsOf: candidate.url, options: [.mappedIfSafe]),
              !data.prefix(8_192).contains(0),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }

        let document = IndexedDocument(text: text, fileByteCount: fileSize)
        if cachedRevision == revision,
           cachedStorageBytes + document.storageByteCount <= Self.maximumCachedStorageBytes {
            cachedDocuments[candidate.id] = document
            cachedStorageBytes += document.storageByteCount
        }
        return document
    }

    private nonisolated static func lineMatches(
        in line: Substring,
        queryText: String,
        comparisonOptions: String.CompareOptions,
        matchesWholeWords: Bool
    ) -> (firstRange: Range<Substring.Index>, count: Int)? {
        var firstRange: Range<Substring.Index>?
        var count = 0
        var searchStart = line.startIndex

        while searchStart < line.endIndex,
              let range = line.range(
                  of: queryText,
                  options: comparisonOptions,
                  range: searchStart..<line.endIndex
              ) {
            if !matchesWholeWords || isWholeWord(range, in: line) {
                firstRange = firstRange ?? range
                count += 1
            }
            searchStart = range.upperBound
        }
        guard let firstRange else { return nil }
        return (firstRange, count)
    }

    private nonisolated static func isWholeWord(
        _ range: Range<Substring.Index>,
        in line: Substring
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

    private nonisolated static func excerpt(
        line: Substring,
        matchRange: Range<Substring.Index>
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
            prefix + String(line[excerptStart..<matchRange.lowerBound]),
            String(line[matchRange]),
            String(line[matchRange.upperBound..<excerptEnd]) + suffix
        )
    }
}

@MainActor
@Observable
final class WorkspaceSearchModel {
    nonisolated static let defaultDebounceDuration: Duration = .milliseconds(300)

    private(set) var mode: WorkspaceSearchMode = .text
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
    let gemmaSearch: WorkspaceGemmaSearchModel?
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
        gemmaSearch: WorkspaceGemmaSearchModel? = nil,
        ignoredPaths: @escaping @MainActor () -> Set<String> = { [] },
        debounceDuration: Duration = defaultDebounceDuration
    ) {
        self.searcher = searcher
        self.gemmaSearch = gemmaSearch
        self.ignoredPaths = ignoredPaths
        self.debounceDuration = debounceDuration
    }

    var supportsGemma: Bool { gemmaSearch != nil }

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

    var needsGemmaSearch: Bool {
        gemmaSearch?.needsSearch(for: query) ?? false
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
        if mode == .text {
            scheduleSearch()
        } else if gemmaSearch?.isRunning == true {
            gemmaSearch?.stop()
        }
    }

    func setMode(_ mode: WorkspaceSearchMode) {
        guard supportsGemma, self.mode != mode else { return }
        self.mode = mode
        switch mode {
        case .text:
            gemmaSearch?.close()
            scheduleSearch()
        case .gemma:
            cancelDebounce()
            cancelSearch()
        }
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

    func searchGemma() {
        guard mode == .gemma, let gemmaSearch else { return }
        cancelDebounce()
        cancelSearch()
        gemmaSearch.search(query)
    }

    func stopGemma() {
        gemmaSearch?.stop()
    }

    func moveSelection(by offset: Int) {
        if mode == .gemma {
            gemmaSearch?.moveSelection(by: offset)
            return
        }
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
        await gemmaSearch?.settle()
    }

    func dismiss() {
        if isSearching {
            activeRevision = nil
        }
        cancelDebounce()
        cancelSearch()
        gemmaSearch?.close()
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
