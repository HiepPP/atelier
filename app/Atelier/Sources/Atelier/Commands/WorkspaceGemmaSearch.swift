import Foundation
import Observation

nonisolated enum WorkspaceSearchMode: String, CaseIterable, Sendable {
    case text = "Text"
    case gemma = "Gemma"
}

nonisolated struct WorkspaceGemmaSearchSource: Identifiable, Equatable, Sendable {
    let path: String
    let lineNumber: Int
    let excerpt: String

    var id: String { "\(path):\(lineNumber)" }

    init(reference: WorkspaceToolReference) {
        path = reference.path
        lineNumber = reference.lineNumber
        excerpt = reference.excerpt
    }
}

nonisolated struct WorkspaceGemmaSearchToolContext: Sendable {
    let revision: Int
    let ignoredPaths: Set<String>
}

@MainActor
final class WorkspaceGemmaSearchRuntimeContext {
    var revision = 0
}

nonisolated protocol WorkspaceGemmaSearching: Sendable {
    func events(for query: String) async -> AsyncThrowingStream<GemmaAgentEvent, Error>
    func cancel() async
}

private nonisolated enum WorkspaceGemmaSearchToolName: String, Sendable {
    case queryCodebase = "query_codebase"
    case contextSymbol = "context_symbol"

    static let definitions: [OllamaToolDefinition] = [
        OllamaToolDefinition(
            function: OllamaFunctionDefinition(
                name: queryCodebase.rawValue,
                description: """
                    Search the GitNexus code graph for architecture, concepts, and execution flows. \
                    Use search_workspace instead for exact text, identifiers, errors, and uncommitted source.
                    """,
                parameters: OllamaToolParameters(
                    properties: [
                        "search_query": OllamaToolProperty(
                            type: "string",
                            description: "Natural-language or keyword description of code behavior."
                        ),
                        "task_context": OllamaToolProperty(
                            type: "string",
                            description: "Optional work context that helps rank results."
                        ),
                        "goal": OllamaToolProperty(
                            type: "string",
                            description: "Optional statement of what should be found."
                        )
                    ],
                    required: ["search_query"]
                )
            )
        ),
        OllamaToolDefinition(
            function: OllamaFunctionDefinition(
                name: contextSymbol.rawValue,
                description: """
                    Inspect callers, callees, relations, and execution-flow membership for one GitNexus symbol. \
                    Prefer the exact UID returned by query_codebase.
                    """,
                parameters: OllamaToolParameters(
                    properties: [
                        "uid": OllamaToolProperty(
                            type: "string",
                            description: "Exact GitNexus symbol UID returned by query_codebase."
                        ),
                        "name": OllamaToolProperty(
                            type: "string",
                            description: "Symbol name when an exact UID is unavailable."
                        ),
                        "file_path": OllamaToolProperty(
                            type: "string",
                            description: "Optional workspace-relative path used to disambiguate the symbol."
                        ),
                        "kind": OllamaToolProperty(
                            type: "string",
                            description: "Optional symbol kind, such as Function, Class, or Method."
                        )
                    ],
                    required: []
                )
            )
        )
    ]
}

actor WorkspaceGemmaSearchRuntime: WorkspaceGemmaSearching {
    private static let systemPrompt = """
        You are Atelier's read-only code search assistant. Use search_workspace for exact text, identifiers, errors, and current working-tree content. Use query_codebase for natural-language architecture and execution-flow questions. Use context_symbol after query_codebase to inspect an exact symbol's callers, callees, and process membership. Use read_file to verify graph conclusions against current source before answering because the GitNexus index may not contain uncommitted changes. Cite every conclusion with workspace-relative path:line. If GitNexus is unavailable, say so and continue with search_workspace and read_file. Never claim to edit files, run commands, or inspect Git or terminal state.
        """

    private let runtime: GemmaAgentRuntime

    init(
        client: any OllamaChatStreaming,
        tools: any WorkspaceToolExecuting
    ) {
        let workspaceNames: Set<String> = [
            WorkspaceToolName.searchWorkspace.rawValue,
            WorkspaceToolName.readFile.rawValue
        ]
        let definitions = WorkspaceToolName.definitions.filter {
            workspaceNames.contains($0.function.name)
        } + WorkspaceGemmaSearchToolName.definitions
        runtime = GemmaAgentRuntime(
            client: client,
            tools: tools,
            systemPrompt: Self.systemPrompt,
            toolDefinitions: definitions
        )
    }

    func events(for query: String) async -> AsyncThrowingStream<GemmaAgentEvent, Error> {
        await runtime.reset()
        return await runtime.events(for: query)
    }

    func cancel() async {
        await runtime.cancel()
    }
}

actor WorkspaceGemmaToolExecutor: WorkspaceToolExecuting {
    static let maximumSources = 100

    private let workspaceRoot: URL
    private let searcher: any WorkspaceContentSearching
    private let reader: any WorkspaceToolExecuting
    private let gitNexus: (any GitNexusCodeIntelligence)?
    private let context: @MainActor @Sendable () -> WorkspaceGemmaSearchToolContext

    init(
        workspaceRoot: URL,
        searcher: any WorkspaceContentSearching,
        reader: any WorkspaceToolExecuting,
        gitNexus: (any GitNexusCodeIntelligence)? = nil,
        context: @escaping @MainActor @Sendable () -> WorkspaceGemmaSearchToolContext
    ) {
        self.workspaceRoot = workspaceRoot.standardizedFileURL.resolvingSymlinksInPath()
        self.searcher = searcher
        self.reader = reader
        self.gitNexus = gitNexus
        self.context = context
    }

    func execute(_ call: OllamaToolCall) async throws -> WorkspaceToolResult {
        do {
            try Task.checkCancellation()
            switch call.function.name {
            case WorkspaceToolName.searchWorkspace.rawValue:
                let input: WorkspaceSearchInput = try Self.decode(call.function.arguments)
                return try await search(input)
            case WorkspaceToolName.readFile.rawValue:
                let input: WorkspaceReadFileInput = try Self.decode(call.function.arguments)
                return try await read(input, call: call)
            case WorkspaceGemmaSearchToolName.queryCodebase.rawValue:
                let input: GitNexusQueryInput = try Self.decode(call.function.arguments)
                return try await queryCodebase(input)
            case WorkspaceGemmaSearchToolName.contextSymbol.rawValue:
                let input: GitNexusContextInput = try Self.decode(call.function.arguments)
                return try await contextSymbol(input)
            default:
                throw WorkspaceToolError.unknownTool(call.function.name)
            }
        } catch is CancellationError {
            throw WorkspaceToolError.cancelled
        } catch let error as WorkspaceToolError {
            throw error
        } catch {
            throw WorkspaceToolError.invalidArguments(
                String(error.localizedDescription.prefix(256))
            )
        }
    }

    private func queryCodebase(_ input: GitNexusQueryInput) async throws -> WorkspaceToolResult {
        guard let gitNexus else { return gitNexusUnavailable() }
        do {
            let result = try await gitNexus.query(input)
            return WorkspaceToolResult(
                content: result.content,
                references: result.references
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return gitNexusUnavailable(error)
        }
    }

    private func contextSymbol(_ input: GitNexusContextInput) async throws -> WorkspaceToolResult {
        guard let gitNexus else { return gitNexusUnavailable() }
        do {
            let result = try await gitNexus.context(input)
            return WorkspaceToolResult(
                content: result.content,
                references: result.references
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return gitNexusUnavailable(error)
        }
    }

    private func gitNexusUnavailable(_ error: Error? = nil) -> WorkspaceToolResult {
        let detail = error?.localizedDescription ?? "GitNexus is unavailable."
        return WorkspaceToolResult(
            content: """
                \(detail) Continue with search_workspace and read_file. \
                State clearly that GitNexus graph search was unavailable.
                """
        )
    }

    private func search(_ input: WorkspaceSearchInput) async throws -> WorkspaceToolResult {
        let query = input.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, query.count <= 500 else {
            throw WorkspaceToolError.invalidArguments("Search query is empty or too long.")
        }

        let state = await context()
        let collector = await MainActor.run {
            WorkspaceGemmaSearchCollector(limit: Self.maximumSources)
        }
        let summary = try await searcher.search(
            query: WorkspaceSearchQuery(
                text: query,
                isCaseSensitive: false,
                matchesWholeWords: false,
                includesIgnoredFiles: false
            ),
            revision: state.revision,
            ignoredPaths: state.ignoredPaths
        ) { batch in
            collector.append(batch)
        }
        let collected = await collector.result()
        let references = collected.matches.map { match in
            WorkspaceToolReference(
                path: match.candidate.relativePath,
                lineNumber: match.lineNumber,
                excerpt: match.leadingText + match.matchedText + match.trailingText
            )
        }
        let content = references.isEmpty
            ? "No matches."
            : references.map {
                "\($0.path):\($0.lineNumber): \($0.excerpt)"
            }.joined(separator: "\n")
        return WorkspaceToolResult(
            content: content,
            references: references,
            truncated: summary.isTruncated || collected.didOverflow
        )
    }

    private func read(
        _ input: WorkspaceReadFileInput,
        call: OllamaToolCall
    ) async throws -> WorkspaceToolResult {
        let result = try await reader.execute(call)
        let path = relativePath(for: input.path)
        let lineNumber = max(1, input.startLine ?? 1)
        let excerpt = result.content.split(
            separator: "\n",
            maxSplits: 1,
            omittingEmptySubsequences: false
        ).first.map(String.init) ?? ""
        return WorkspaceToolResult(
            content: result.content,
            referencedFiles: [path],
            references: [
                WorkspaceToolReference(
                    path: path,
                    lineNumber: lineNumber,
                    excerpt: excerpt
                )
            ],
            truncated: result.truncated
        )
    }

    private func relativePath(for path: String) -> String {
        guard path.hasPrefix("/") else { return path }
        let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        let rootComponents = workspaceRoot.pathComponents
        let components = url.pathComponents
        guard components.starts(with: rootComponents) else { return path }
        return components.dropFirst(rootComponents.count).joined(separator: "/")
    }

    private nonisolated static func decode<Value: Decodable>(
        _ arguments: [String: OllamaJSONValue]
    ) throws -> Value {
        try JSONDecoder().decode(Value.self, from: JSONEncoder().encode(arguments))
    }
}

@MainActor
private final class WorkspaceGemmaSearchCollector {
    private let limit: Int
    private var matches: [WorkspaceSearchMatch] = []
    private var didOverflow = false

    init(limit: Int) {
        self.limit = limit
    }

    func append(_ batch: [WorkspaceSearchMatch]) {
        for match in batch {
            guard !WorkspaceToolPathPolicy.isSensitive(
                relativePath: match.candidate.relativePath
            ) else {
                continue
            }
            guard matches.count < limit else {
                didOverflow = true
                continue
            }
            matches.append(match)
        }
    }

    func result() -> (matches: [WorkspaceSearchMatch], didOverflow: Bool) {
        (matches, didOverflow)
    }
}

@MainActor
@Observable
final class WorkspaceGemmaSearchModel {
    private(set) var answer = ""
    private(set) var sources: [WorkspaceGemmaSearchSource] = []
    private(set) var selectedSourceID: String?
    private(set) var status: GemmaAgentStatus = .idle
    private(set) var activeQuery: String?
    private(set) var errorMessage: String?
    private(set) var recoverySuggestion: String?

    private let searcher: any WorkspaceGemmaSearching
    private var generation = 0
    private var runTask: Task<Void, Never>?
    @ObservationIgnored private var pendingDelta = ""
    @ObservationIgnored private var deltaFlushTask: Task<Void, Never>?

    init(searcher: any WorkspaceGemmaSearching) {
        self.searcher = searcher
    }

    var isRunning: Bool { status == .running }

    var selection: WorkspaceGemmaSearchSource? {
        guard let selectedSourceID else { return nil }
        return sources.first { $0.id == selectedSourceID }
    }

    func needsSearch(for query: String) -> Bool {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty, cleanQuery.count <= 500 else { return false }
        return activeQuery != cleanQuery || status != .completed
    }

    func search(_ query: String) {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty, cleanQuery.count <= 500 else {
            errorMessage = query.isEmpty
                ? nil
                : "Search queries are limited to 500 characters."
            return
        }

        generation &+= 1
        let currentGeneration = generation
        runTask?.cancel()
        flushPendingDelta()
        answer = ""
        sources = []
        selectedSourceID = nil
        activeQuery = cleanQuery
        errorMessage = nil
        recoverySuggestion = nil
        status = .running

        let searcher = searcher
        runTask = Task { [weak self] in
            do {
                let events = await searcher.events(for: cleanQuery)
                for try await event in events {
                    guard let self,
                          !Task.isCancelled,
                          self.generation == currentGeneration else {
                        return
                    }
                    self.apply(event)
                }
            } catch is CancellationError {
                return
            } catch let error as GemmaAgentRuntimeError where error == .cancelled {
                return
            } catch {
                guard let self,
                      !Task.isCancelled,
                      self.generation == currentGeneration else {
                    return
                }
                self.flushPendingDelta()
                self.status = .failed
                self.runTask = nil
                self.errorMessage = error.localizedDescription
                self.recoverySuggestion = (error as? OllamaCloudError)?.recoverySuggestion
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        generation &+= 1
        flushPendingDelta()
        runTask?.cancel()
        runTask = nil
        status = .cancelled
        let searcher = searcher
        Task { await searcher.cancel() }
    }

    func close() {
        generation &+= 1
        flushPendingDelta()
        runTask?.cancel()
        runTask = nil
        if isRunning {
            status = .cancelled
        }
        let searcher = searcher
        Task { await searcher.cancel() }
    }

    func moveSelection(by offset: Int) {
        let ids = sources.map(\.id)
        guard !ids.isEmpty else {
            selectedSourceID = nil
            return
        }
        let currentIndex = selectedSourceID.flatMap(ids.firstIndex(of:)) ?? 0
        selectedSourceID = ids[min(max(0, currentIndex + offset), ids.count - 1)]
    }

    func selectSource(id: String?) {
        guard let id, sources.contains(where: { $0.id == id }) else { return }
        selectedSourceID = id
    }

    func settle() async {
        await runTask?.value
    }

    private func apply(_ event: GemmaAgentEvent) {
        switch event {
        case .assistantDelta(let delta):
            pendingDelta.append(delta)
            scheduleDeltaFlush()
        case .toolStarted:
            flushPendingDelta()
        case .toolFinished(let activity):
            flushPendingDelta()
            append(activity.references)
        case .completed:
            flushPendingDelta()
            status = .completed
            runTask = nil
        }
    }

    private func append(_ references: [WorkspaceToolReference]) {
        for reference in references {
            let source = WorkspaceGemmaSearchSource(reference: reference)
            guard !sources.contains(where: { $0.id == source.id }) else { continue }
            sources.append(source)
            if selectedSourceID == nil {
                selectedSourceID = source.id
            }
            if sources.count == WorkspaceGemmaToolExecutor.maximumSources {
                return
            }
        }
    }

    private func scheduleDeltaFlush() {
        guard deltaFlushTask == nil else { return }
        deltaFlushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(80))
            guard let self, !Task.isCancelled else { return }
            self.deltaFlushTask = nil
            self.flushPendingDelta()
        }
    }

    private func flushPendingDelta() {
        deltaFlushTask?.cancel()
        deltaFlushTask = nil
        guard !pendingDelta.isEmpty else { return }
        answer.append(pendingDelta)
        pendingDelta = ""
    }

    isolated deinit {
        runTask?.cancel()
        deltaFlushTask?.cancel()
    }
}
