import Foundation
import Testing
@testable import Atelier

@Suite("Workspace search")
@MainActor
struct WorkspaceSearchTests {
    @Test("Content search supports case, whole-word, ignored, and binary rules")
    func contentRules() async throws {
        let root = temporaryDirectory("workspace-search-rules")
        defer { try? FileManager.default.removeItem(at: root) }
        try write(
            "let Needle = 1\nneedle needle\nneedles\n",
            to: root.appendingPathComponent("Sources/One.swift")
        )
        try write(
            "secret needle\n",
            to: root.appendingPathComponent("Ignored/Hidden.swift")
        )
        try write(
            Data([0, 1, 2, 3]),
            to: root.appendingPathComponent("Sources/Binary.dat")
        )

        let service = WorkspaceSearchService(
            fileIndex: WorkspaceFileIndex(rootURL: root)
        )

        let regular = try await collect(
            service: service,
            query: WorkspaceSearchQuery(
                text: "needle",
                isCaseSensitive: false,
                matchesWholeWords: false,
                includesIgnoredFiles: false
            ),
            ignoredPaths: ["Ignored"]
        )
        #expect(regular.summary.matchCount == 4)
        #expect(regular.matches.map(\.lineNumber) == [1, 2, 3])
        #expect(regular.matches.allSatisfy { $0.candidate.relativePath == "Sources/One.swift" })

        let wholeWord = try await collect(
            service: service,
            query: WorkspaceSearchQuery(
                text: "needle",
                isCaseSensitive: false,
                matchesWholeWords: true,
                includesIgnoredFiles: false
            ),
            ignoredPaths: ["Ignored"]
        )
        #expect(wholeWord.summary.matchCount == 3)
        #expect(wholeWord.matches.map(\.lineNumber) == [1, 2])

        let caseSensitive = try await collect(
            service: service,
            query: WorkspaceSearchQuery(
                text: "Needle",
                isCaseSensitive: true,
                matchesWholeWords: false,
                includesIgnoredFiles: false
            ),
            ignoredPaths: ["Ignored"]
        )
        #expect(caseSensitive.summary.matchCount == 1)

        let includingIgnored = try await collect(
            service: service,
            query: WorkspaceSearchQuery(
                text: "secret",
                isCaseSensitive: false,
                matchesWholeWords: false,
                includesIgnoredFiles: true
            ),
            ignoredPaths: ["Ignored"]
        )
        #expect(includingIgnored.matches.map(\.candidate.relativePath) == ["Ignored/Hidden.swift"])
    }

    @Test("Content search includes text files above one megabyte")
    func searchableEditorSizedFile() async throws {
        let root = temporaryDirectory("workspace-search-editor-sized")
        defer { try? FileManager.default.removeItem(at: root) }
        let content = "let value39 = 39\n" + String(repeating: "x", count: 1_050_000)
        #expect(Data(content.utf8).count > 1_000_000)
        #expect(Data(content.utf8).count <= FileLoader.defaultLimit)
        try write(content, to: root.appendingPathComponent("scroll_perf_test.swift"))

        let result = try await collect(
            service: WorkspaceSearchService(
                fileIndex: WorkspaceFileIndex(rootURL: root)
            ),
            query: WorkspaceSearchQuery(
                text: "value39",
                isCaseSensitive: false,
                matchesWholeWords: false,
                includesIgnoredFiles: false
            ),
            ignoredPaths: []
        )

        #expect(WorkspaceSearchService.maximumFileBytes == FileLoader.defaultLimit)
        #expect(result.matches.map(\.candidate.relativePath) == ["scroll_perf_test.swift"])
        #expect(result.matches.map(\.lineNumber) == [1])
    }

    @Test("Typing waits for the trailing debounce and searches the latest query")
    func debouncedSearch() async {
        let searcher = DelayedWorkspaceSearcher()
        let model = WorkspaceSearchModel(
            searcher: searcher,
            debounceDuration: .milliseconds(20)
        )
        model.present(revision: 0)
        model.updateQuery("one")
        model.updateQuery("two")
        model.updateQuery("fast")

        #expect(model.isWaitingToSearch)
        #expect(await searcher.recordedQueries().isEmpty)

        await model.settleSearch()

        #expect(await searcher.recordedQueries() == ["fast"])
        #expect(model.matches.map(\.matchedText) == ["fast"])
        #expect(!model.isWaitingToSearch)
        #expect(!model.isSearching)
    }

    @Test("New typing cancels a running stale search")
    func runningSearchCancellation() async throws {
        let searcher = DelayedWorkspaceSearcher()
        let model = WorkspaceSearchModel(
            searcher: searcher,
            debounceDuration: .milliseconds(10)
        )
        model.present(revision: 0)
        model.updateQuery("slow")

        try await Task.sleep(for: .milliseconds(20))

        model.updateQuery("fast")
        await model.settleSearch()

        #expect(await searcher.recordedQueries() == ["slow", "fast"])
        #expect(model.matches.map(\.matchedText) == ["fast"])
        #expect(model.selection?.matchedText == "fast")
        #expect(!model.isSearching)
    }

    @Test("Dismissed running searches reopen as needing confirmation")
    func dismissedSearch() {
        let model = WorkspaceSearchModel(searcher: DelayedWorkspaceSearcher())
        model.present(revision: 0)
        model.updateQuery("slow")
        model.search()

        model.dismiss()
        model.present(revision: 0)

        #expect(model.needsSearch)
        #expect(!model.isSearching)
    }

    @Test("Result lines stop at the exact bound")
    func resultBound() async throws {
        let root = temporaryDirectory("workspace-search-bound")
        defer { try? FileManager.default.removeItem(at: root) }
        try write(
            Array(repeating: "needle", count: WorkspaceSearchService.maximumResultLines + 1)
                .joined(separator: "\n"),
            to: root.appendingPathComponent("Many.txt")
        )
        let service = WorkspaceSearchService(
            fileIndex: WorkspaceFileIndex(rootURL: root)
        )

        let result = try await collect(
            service: service,
            query: WorkspaceSearchQuery(
                text: "needle",
                isCaseSensitive: false,
                matchesWholeWords: false,
                includesIgnoredFiles: false
            ),
            ignoredPaths: []
        )

        #expect(result.matches.count == WorkspaceSearchService.maximumResultLines)
        #expect(result.summary.matchCount == WorkspaceSearchService.maximumResultLines)
        #expect(result.summary.isTruncated)
    }

    @Test("Opening a search target requests source mode and its line")
    func sourceReveal() throws {
        let root = temporaryDirectory("workspace-search-reveal")
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURL = root.appendingPathComponent("README.md")
        try write("# One\nTarget\n", to: fileURL)
        let tabs = TerminalTabsModel(workspacePath: root.path)
        defer { tabs.closeAll() }

        tabs.openFile(fileURL, line: 2)
        let session = try #require(tabs.selectedEditor)

        #expect(session.prefersSourceForNavigation)
        #expect(session.navigationRevealRequest?.line == 2)
        session.allowRenderedPreview()
        #expect(!session.prefersSourceForNavigation)
    }

    private func collect(
        service: WorkspaceSearchService,
        query: WorkspaceSearchQuery,
        ignoredPaths: Set<String>
    ) async throws -> (summary: WorkspaceSearchSummary, matches: [WorkspaceSearchMatch]) {
        var matches: [WorkspaceSearchMatch] = []
        let summary = try await service.search(
            query: query,
            revision: 0,
            ignoredPaths: ignoredPaths
        ) { batch in
            matches.append(contentsOf: batch)
        }
        return (summary, matches)
    }

    private func temporaryDirectory(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("atelier-tests-\(name)-\(UUID().uuidString)", isDirectory: true)
    }

    private func write(_ text: String, to url: URL) throws {
        try write(Data(text.utf8), to: url)
    }

    private func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url)
    }
}

private actor DelayedWorkspaceSearcher: WorkspaceContentSearching {
    private var queries: [String] = []

    func search(
        query: WorkspaceSearchQuery,
        revision: Int,
        ignoredPaths: Set<String>,
        onBatch: @escaping @MainActor @Sendable ([WorkspaceSearchMatch]) -> Void
    ) async throws -> WorkspaceSearchSummary {
        queries.append(query.text)
        if query.text == "slow" {
            try await Task.sleep(for: .milliseconds(100))
        }
        try Task.checkCancellation()
        let candidate = AtelierFileCandidate(
            url: URL(fileURLWithPath: "/tmp/\(query.text).swift"),
            relativePath: "\(query.text).swift"
        )
        await onBatch([
            WorkspaceSearchMatch(
                candidate: candidate,
                lineNumber: 1,
                leadingText: "",
                matchedText: query.text,
                trailingText: "",
                matchCount: 1
            )
        ])
        return WorkspaceSearchSummary(
            searchedFileCount: 1,
            matchedFileCount: 1,
            matchCount: 1,
            isTruncated: false
        )
    }

    func recordedQueries() -> [String] {
        queries
    }
}
