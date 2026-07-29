import Foundation
import Testing
@testable import Atelier

@Suite("Workspace search")
@MainActor
struct WorkspaceSearchTests {
    @Test("Default typing debounce is 300 milliseconds")
    func defaultDebounceDuration() {
        #expect(
            WorkspaceSearchModel.defaultDebounceDuration
                == .milliseconds(300)
        )
    }

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

    @Test("Decoded search content is cached until the file revision changes")
    func contentCacheRevision() async throws {
        let root = temporaryDirectory("workspace-search-cache")
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURL = root.appendingPathComponent("Cache.swift")
        try write("let alpha = 1\n", to: fileURL)
        let service = WorkspaceSearchService(
            fileIndex: WorkspaceFileIndex(rootURL: root)
        )

        let initial = try await collect(
            service: service,
            query: searchQuery("alpha"),
            ignoredPaths: [],
            revision: 0
        )
        try write("let beta = 2\n", to: fileURL)
        let cached = try await collect(
            service: service,
            query: searchQuery("alpha"),
            ignoredPaths: [],
            revision: 0
        )
        let refreshed = try await collect(
            service: service,
            query: searchQuery("beta"),
            ignoredPaths: [],
            revision: 1
        )

        #expect(initial.summary.matchCount == 1)
        #expect(cached.summary.matchCount == 1)
        #expect(refreshed.summary.matchCount == 1)
        #expect(
            WorkspaceSearchService.maximumCachedStorageBytes
                == 64 * 1_024 * 1_024
        )
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

    @Test("Gemma mode waits for Return and streams an answer with line sources")
    func gemmaExplicitSubmission() async throws {
        let reference = WorkspaceToolReference(
            path: "Sources/WorkspaceSession.swift",
            lineNumber: 54,
            excerpt: "workspaceSearchModel = WorkspaceSearchModel("
        )
        let gemmaSearcher = ScriptedWorkspaceGemmaSearcher(
            response: .events([
                .assistantDelta("Workspace search is created per session."),
                .toolFinished(
                    GemmaToolActivity(
                        name: WorkspaceToolName.searchWorkspace.rawValue,
                        detail: "Search: workspaceSearchModel",
                        referencedFiles: [reference.path],
                        references: [reference],
                        isComplete: true
                    )
                ),
                .completed
            ])
        )
        let gemmaModel = WorkspaceGemmaSearchModel(searcher: gemmaSearcher)
        let literalSearcher = DelayedWorkspaceSearcher()
        let model = WorkspaceSearchModel(
            searcher: literalSearcher,
            gemmaSearch: gemmaModel,
            debounceDuration: .milliseconds(10)
        )
        model.present(revision: 0)
        model.setMode(.gemma)
        model.updateQuery("Where is workspace search created?")

        try await Task.sleep(for: .milliseconds(30))

        #expect(await literalSearcher.recordedQueries().isEmpty)
        #expect(await gemmaSearcher.recordedQueries().isEmpty)

        model.searchGemma()
        await model.settleSearch()

        #expect(await gemmaSearcher.recordedQueries() == ["Where is workspace search created?"])
        #expect(gemmaModel.answer == "Workspace search is created per session.")
        #expect(
            gemmaModel.sources
                == [
                    WorkspaceGemmaSearchSource(reference: reference)
                ]
        )
        #expect(gemmaModel.selection?.lineNumber == 54)
        #expect(gemmaModel.status == .completed)

        model.dismiss()
        model.present(revision: 0)
        #expect(model.mode == .gemma)
        model.dismiss()
    }

    @Test("Gemma answer file references open their exact source line")
    func gemmaAnswerSourceLinks() {
        let path = "app/Atelier/Sources/Atelier/App/AtelierApp.swift"
        let markdown = WorkspaceGemmaSourceLinkPolicy.linkifiedMarkdown(
            "Open `\(path):5` for the entry point."
        )
        let attributed = AgentMarkdownInlinePolicy.attributedString(markdown)
        let url = attributed.runs.compactMap(\.link).first

        #expect(String(attributed.characters) == "Open \(path):5 for the entry point.")
        #expect(url != nil)
        let source = url.flatMap(WorkspaceGemmaSourceLinkPolicy.source(from:))
        #expect(source?.path == path)
        #expect(source?.lineNumber == 5)
        #expect(source?.excerpt.isEmpty == true)

        let blocks = WorkspaceGemmaSourceLinkPolicy.answerBlocks(
            "Entry point:\n\n`\(path):5`\n\nContains @main."
        )
        #expect(blocks.count == 3)
        #expect(blocks[1].sourceDisplay == "\(path):5")
        #expect(blocks[1].source?.path == path)
        #expect(blocks[1].source?.lineNumber == 5)
    }

    @Test("Stopping Gemma search cancels its dedicated runtime")
    func gemmaCancellation() async {
        let gemmaSearcher = ScriptedWorkspaceGemmaSearcher(response: .waiting)
        let gemmaModel = WorkspaceGemmaSearchModel(searcher: gemmaSearcher)
        let model = WorkspaceSearchModel(
            searcher: DelayedWorkspaceSearcher(),
            gemmaSearch: gemmaModel
        )
        model.present(revision: 0)
        model.setMode(.gemma)
        model.updateQuery("Wait for this search")
        model.searchGemma()
        while await gemmaSearcher.recordedQueries().isEmpty {
            await Task.yield()
        }

        model.stopGemma()
        while await gemmaSearcher.recordedCancelCount() == 0 {
            await Task.yield()
        }

        #expect(gemmaModel.status == .cancelled)
        #expect(!gemmaModel.isRunning)
    }

    @Test("Gemma tools reuse indexed search for editor-sized files")
    func gemmaIndexedSearch() async throws {
        let root = temporaryDirectory("workspace-gemma-indexed")
        defer { try? FileManager.default.removeItem(at: root) }
        let content = "let sharedSearchNeedle = 1\n" + String(repeating: "x", count: 1_050_000)
        try write(content, to: root.appendingPathComponent("Large.swift"))
        try write(
            "sharedSearchNeedle=secret\n",
            to: root.appendingPathComponent(".env")
        )
        let service = WorkspaceSearchService(
            fileIndex: WorkspaceFileIndex(rootURL: root)
        )
        let tools = WorkspaceGemmaToolExecutor(
            workspaceRoot: root,
            searcher: service,
            reader: WorkspaceToolExecutor(workspaceRoot: root),
            context: {
                WorkspaceGemmaSearchToolContext(revision: 0, ignoredPaths: [])
            }
        )

        let result = try await tools.execute(
            OllamaToolCall(
                function: OllamaFunctionCall(
                    name: WorkspaceToolName.searchWorkspace.rawValue,
                    arguments: ["query": .string("sharedSearchNeedle")]
                )
            )
        )

        #expect(result.references.count == 1)
        #expect(result.references.first?.path == "Large.swift")
        #expect(result.references.first?.lineNumber == 1)
        #expect(result.content.contains("Large.swift:1"))
    }

    @Test("Dedicated Gemma runtime exposes literal, read, query, and context tools only")
    func gemmaToolScope() async throws {
        let client = ScriptedOllamaClient(
            responses: [
                .chunks([
                    OllamaChatChunk(
                        message: OllamaChatMessage(
                            role: .assistant,
                            content: "Done"
                        ),
                        done: true
                    )
                ])
            ]
        )
        let runtime = WorkspaceGemmaSearchRuntime(
            client: client,
            tools: RecordingWorkspaceTools()
        )

        let events = await runtime.events(for: "Find the session")
        for try await _ in events {}
        let requests = await client.requests
        let tools = try #require(requests.first?.tools)

        #expect(
            Set(tools.map(\.function.name))
                == [
                    WorkspaceToolName.searchWorkspace.rawValue,
                    WorkspaceToolName.readFile.rawValue,
                    "query_codebase",
                    "context_symbol"
                ]
        )
        #expect(
            WorkspaceToolName.definitions.allSatisfy {
                $0.function.name != "query_codebase"
                    && $0.function.name != "context_symbol"
            }
        )
    }

    @Test("Gemma query and context tools forward bounded graph requests")
    func gemmaGitNexusTools() async throws {
        let reference = WorkspaceToolReference(
            path: "Sources/Search.swift",
            lineNumber: 12,
            excerpt: "SearchRuntime - UID: Class:Sources/Search.swift:SearchRuntime"
        )
        let gitNexus = RecordingGitNexusCodeIntelligence(
            result: GitNexusCodeIntelligenceResult(
                content: "Graph result",
                references: [reference]
            )
        )
        let tools = WorkspaceGemmaToolExecutor(
            workspaceRoot: URL(fileURLWithPath: "/tmp"),
            searcher: DelayedWorkspaceSearcher(),
            reader: RecordingWorkspaceTools(),
            gitNexus: gitNexus,
            context: {
                WorkspaceGemmaSearchToolContext(revision: 0, ignoredPaths: [])
            }
        )

        let queryResult = try await tools.execute(
            toolCall(
                "query_codebase",
                arguments: [
                    "search_query": .string("workspace search flow"),
                    "task_context": .string("adding GitNexus"),
                    "goal": .string("find routing")
                ]
            )
        )
        let contextResult = try await tools.execute(
            toolCall(
                "context_symbol",
                arguments: [
                    "uid": .string("Class:Sources/Search.swift:SearchRuntime")
                ]
            )
        )

        #expect(
            await gitNexus.recordedQueries()
                == [
                    GitNexusQueryInput(
                        searchQuery: "workspace search flow",
                        taskContext: "adding GitNexus",
                        goal: "find routing"
                    )
                ]
        )
        #expect(
            await gitNexus.recordedContexts()
                == [
                    GitNexusContextInput(
                        name: nil,
                        uid: "Class:Sources/Search.swift:SearchRuntime",
                        filePath: nil,
                        kind: nil
                    )
                ]
        )
        #expect(queryResult.references == [reference])
        #expect(contextResult.references == [reference])
    }

    @Test("GitNexus failure keeps literal search available")
    func gemmaGitNexusFallback() async throws {
        let tools = WorkspaceGemmaToolExecutor(
            workspaceRoot: URL(fileURLWithPath: "/tmp"),
            searcher: DelayedWorkspaceSearcher(),
            reader: RecordingWorkspaceTools(),
            gitNexus: RecordingGitNexusCodeIntelligence(error: .unavailable),
            context: {
                WorkspaceGemmaSearchToolContext(revision: 0, ignoredPaths: [])
            }
        )

        let result = try await tools.execute(
            toolCall(
                "query_codebase",
                arguments: ["search_query": .string("workspace flow")]
            )
        )

        #expect(result.references.isEmpty)
        #expect(result.content.contains("Continue with search_workspace and read_file."))
        #expect(result.content.contains("graph search was unavailable"))
    }

    @Test("Cancelling a GitNexus tool cancels the Gemma search tool call")
    func gemmaGitNexusCancellation() async {
        let gitNexus = RecordingGitNexusCodeIntelligence(waitForCancellation: true)
        let tools = WorkspaceGemmaToolExecutor(
            workspaceRoot: URL(fileURLWithPath: "/tmp"),
            searcher: DelayedWorkspaceSearcher(),
            reader: RecordingWorkspaceTools(),
            gitNexus: gitNexus,
            context: {
                WorkspaceGemmaSearchToolContext(revision: 0, ignoredPaths: [])
            }
        )
        let task = Task {
            try await tools.execute(
                toolCall(
                    "query_codebase",
                    arguments: ["search_query": .string("workspace flow")]
                )
            )
        }
        while await gitNexus.recordedQueries().isEmpty {
            await Task.yield()
        }

        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected the GitNexus tool call to be cancelled.")
        } catch let error as WorkspaceToolError {
            #expect(error == .cancelled)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("GitNexus responses expose UIDs and filter unsafe source paths")
    func gitNexusResponseParsing() throws {
        let root = temporaryDirectory("gitnexus-parser")
        defer { try? FileManager.default.removeItem(at: root) }
        try write("final class SearchRuntime {}\n", to: root.appendingPathComponent("Sources/Search.swift"))
        try write("TOKEN=secret\n", to: root.appendingPathComponent(".env"))
        let queryJSON = """
            {
              "processes": [
                {"id": "proc_search", "summary": "Search overlay to runtime"}
              ],
              "process_symbols": [
                {
                  "id": "Class:Sources/Search.swift:SearchRuntime",
                  "name": "SearchRuntime",
                  "filePath": "Sources/Search.swift",
                  "startLine": 1,
                  "process_id": "proc_search"
                },
                {
                  "id": "File:.env",
                  "name": ".env",
                  "filePath": ".env",
                  "startLine": 1
                },
                {
                  "id": "File:/tmp/outside.swift",
                  "name": "outside.swift",
                  "filePath": "/tmp/outside.swift",
                  "startLine": 1
                }
              ],
              "definitions": []
            }
            """

        let query = try GitNexusResponseParser.query(
            text: queryJSON + "\n---\nNext: context({name: \"SearchRuntime\"})",
            workspaceRoot: root,
            searchMode: "BM25 only; semantic vector search is unavailable."
        )
        let context = try GitNexusResponseParser.context(
            text: """
                {
                  "symbol": {
                    "uid": "Class:Sources/Search.swift:SearchRuntime",
                    "name": "SearchRuntime",
                    "kind": "Class",
                    "filePath": "Sources/Search.swift",
                    "startLine": 1
                  },
                  "incoming": {},
                  "outgoing": {},
                  "processes": [
                    {
                      "id": "proc_search",
                      "name": "Open Search to Gemma",
                      "step_index": 1,
                      "step_count": 3
                    }
                  ]
                }
                """,
            workspaceRoot: root
        )

        #expect(query.references.map(\.path) == ["Sources/Search.swift"])
        #expect(query.content.contains("BM25 only"))
        #expect(query.content.contains("UID: Class:Sources/Search.swift:SearchRuntime"))
        #expect(context.references.map(\.path) == ["Sources/Search.swift"])
        #expect(context.content.contains("selected symbol"))
        #expect(context.content.contains("UID: Class:Sources/Search.swift:SearchRuntime"))
        #expect(context.content.contains("Open Search to Gemma, step 2 of 3"))
    }

    @Test("GitNexus vector-index metadata enables hybrid search mode")
    func gitNexusHybridSearchMode() {
        let hybrid = GitNexusMCPClient.searchMode(
            embeddings: 9_715,
            vectorSearchStatus: "vector-index"
        )
        let missingEmbeddings = GitNexusMCPClient.searchMode(
            embeddings: 0,
            vectorSearchStatus: "vector-index"
        )
        let unavailableVectorSearch = GitNexusMCPClient.searchMode(
            embeddings: 9_715,
            vectorSearchStatus: "unavailable"
        )

        #expect(hybrid.contains("Hybrid BM25 and vector search"))
        #expect(hybrid.contains("reciprocal rank fusion"))
        #expect(missingEmbeddings.contains("BM25 only"))
        #expect(unavailableVectorSearch.contains("BM25 only"))
    }

    @Test(
        "GitNexus MCP client queries and follows an indexed symbol",
        .enabled(
            if: ProcessInfo.processInfo.environment["ATELIER_GITNEXUS_INTEGRATION"] == "1"
        )
    )
    func gitNexusMCPIntegration() async throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let client = GitNexusMCPClient(workspaceRoot: root)
        do {
            let query = try await client.query(
                GitNexusQueryInput(
                    searchQuery: "WorkspaceGemmaSearchRuntime",
                    taskContext: "testing Search All Files Gemma integration",
                    goal: "find the dedicated search runtime"
                )
            )
            let reference = try #require(
                query.references.first {
                    $0.excerpt.contains("WorkspaceGemmaSearchRuntime")
                        && $0.excerpt.contains("UID: ")
                }
            )
            let uid = try #require(
                reference.excerpt.components(separatedBy: "UID: ").last
            )
            let context = try await client.context(
                GitNexusContextInput(
                    name: nil,
                    uid: uid,
                    filePath: nil,
                    kind: nil
                )
            )

            #expect(query.content.contains("GitNexus search mode:"))
            #expect(context.content.contains("WorkspaceGemmaSearchRuntime"))
            #expect(!context.references.isEmpty)
            await client.stop()
        } catch {
            await client.stop()
            throw error
        }
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

        while await searcher.recordedQueries().isEmpty {
            await Task.yield()
        }

        model.updateQuery("fast")
        await model.settleSearch()

        let recorded = await searcher.recordedQueries()
        #expect(recorded == ["slow", "fast"])
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
        ignoredPaths: Set<String>,
        revision: Int = 0
    ) async throws -> (summary: WorkspaceSearchSummary, matches: [WorkspaceSearchMatch]) {
        var matches: [WorkspaceSearchMatch] = []
        let summary = try await service.search(
            query: query,
            revision: revision,
            ignoredPaths: ignoredPaths
        ) { batch in
            matches.append(contentsOf: batch)
        }
        return (summary, matches)
    }

    private func searchQuery(_ text: String) -> WorkspaceSearchQuery {
        WorkspaceSearchQuery(
            text: text,
            isCaseSensitive: false,
            matchesWholeWords: false,
            includesIgnoredFiles: false
        )
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

    private func toolCall(
        _ name: String,
        arguments: [String: OllamaJSONValue]
    ) -> OllamaToolCall {
        OllamaToolCall(
            function: OllamaFunctionCall(name: name, arguments: arguments)
        )
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

private nonisolated enum ScriptedWorkspaceGemmaResponse: Sendable {
    case events([GemmaAgentEvent])
    case waiting
}

private actor ScriptedWorkspaceGemmaSearcher: WorkspaceGemmaSearching {
    private let response: ScriptedWorkspaceGemmaResponse
    private var queries: [String] = []
    private var cancelCount = 0

    init(response: ScriptedWorkspaceGemmaResponse) {
        self.response = response
    }

    func events(for query: String) -> AsyncThrowingStream<GemmaAgentEvent, Error> {
        queries.append(query)
        return AsyncThrowingStream { continuation in
            switch response {
            case .events(let events):
                for event in events {
                    continuation.yield(event)
                }
                continuation.finish()
            case .waiting:
                continuation.onTermination = { @Sendable _ in }
            }
        }
    }

    func cancel() {
        cancelCount += 1
    }

    func recordedQueries() -> [String] {
        queries
    }

    func recordedCancelCount() -> Int {
        cancelCount
    }
}

private actor RecordingGitNexusCodeIntelligence: GitNexusCodeIntelligence {
    private let result: GitNexusCodeIntelligenceResult
    private let error: GitNexusMCPError?
    private let waitForCancellation: Bool
    private var queries: [GitNexusQueryInput] = []
    private var contexts: [GitNexusContextInput] = []
    private var stopCount = 0

    init(
        result: GitNexusCodeIntelligenceResult = GitNexusCodeIntelligenceResult(
            content: "Graph result",
            references: []
        ),
        error: GitNexusMCPError? = nil,
        waitForCancellation: Bool = false
    ) {
        self.result = result
        self.error = error
        self.waitForCancellation = waitForCancellation
    }

    func query(_ input: GitNexusQueryInput) async throws -> GitNexusCodeIntelligenceResult {
        queries.append(input)
        if waitForCancellation {
            try await Task.sleep(for: .seconds(60))
        }
        if let error { throw error }
        return result
    }

    func context(_ input: GitNexusContextInput) async throws -> GitNexusCodeIntelligenceResult {
        contexts.append(input)
        if waitForCancellation {
            try await Task.sleep(for: .seconds(60))
        }
        if let error { throw error }
        return result
    }

    func stop() {
        stopCount += 1
    }

    func recordedQueries() -> [GitNexusQueryInput] {
        queries
    }

    func recordedContexts() -> [GitNexusContextInput] {
        contexts
    }
}
