import Foundation

nonisolated struct GemmaToolActivity: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let detail: String
    let referencedFiles: [String]
    let isComplete: Bool

    init(
        id: UUID = UUID(),
        name: String,
        detail: String,
        referencedFiles: [String] = [],
        isComplete: Bool = false
    ) {
        self.id = id
        self.name = name
        self.detail = detail
        self.referencedFiles = referencedFiles
        self.isComplete = isComplete
    }
}

nonisolated enum GemmaAgentEvent: Equatable, Sendable {
    case assistantDelta(String)
    case toolStarted(GemmaToolActivity)
    case toolFinished(GemmaToolActivity)
    case completed
}

nonisolated enum GemmaAgentRuntimeError: LocalizedError, Equatable, Sendable {
    case toolLimitExceeded
    case transcriptLimitExceeded
    case emptyResponse
    case cancelled

    var errorDescription: String? {
        switch self {
        case .toolLimitExceeded:
            return "Gemma reached the read-only tool limit for this prompt."
        case .transcriptLimitExceeded:
            return "This Gemma session is full. Clear it before sending another prompt."
        case .emptyResponse:
            return "Gemma returned no text or tool calls."
        case .cancelled:
            return "Gemma run cancelled."
        }
    }
}

actor GemmaAgentRuntime {
    private static let systemPrompt = """
        You are Atelier's read-only workspace assistant. Inspect the workspace using only the provided tools. Never claim to edit files or run commands. Prefer focused searches and bounded file reads. Cite workspace-relative paths and line numbers in the final answer.
        """
    private static let maximumToolIterations = 8
    private static let maximumHistoryCharacters = 240_000
    private static let maximumToolResultCharacters = 50_000

    private let client: any OllamaChatStreaming
    private let tools: any WorkspaceToolExecuting
    private var history: [OllamaChatMessage] = [
        OllamaChatMessage(role: .system, content: systemPrompt)
    ]
    private var activeTask: Task<Void, Never>?

    init(client: any OllamaChatStreaming, tools: any WorkspaceToolExecuting) {
        self.client = client
        self.tools = tools
    }

    func events(for prompt: String) -> AsyncThrowingStream<GemmaAgentEvent, Error> {
        cancelActiveTask()
        let stream = AsyncThrowingStream<GemmaAgentEvent, Error> { continuation in
            let task = Task {
                do {
                    try await run(prompt: prompt, continuation: continuation)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: GemmaAgentRuntimeError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
            activeTask = task
        }
        return stream
    }

    func cancel() async {
        cancelActiveTask()
        await client.cancel()
    }

    func reset() async {
        await cancel()
        history = [OllamaChatMessage(role: .system, content: Self.systemPrompt)]
    }

    private func run(
        prompt: String,
        continuation: AsyncThrowingStream<GemmaAgentEvent, Error>.Continuation
    ) async throws {
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPrompt.isEmpty else { throw GemmaAgentRuntimeError.emptyResponse }
        guard historyCharacterCount + cleanPrompt.count <= Self.maximumHistoryCharacters else {
            throw GemmaAgentRuntimeError.transcriptLimitExceeded
        }
        var runHistory = history
        runHistory.append(OllamaChatMessage(role: .user, content: cleanPrompt))

        var toolIterations = 0
        while true {
            try Task.checkCancellation()
            let request = OllamaChatRequest(
                messages: runHistory,
                tools: WorkspaceToolName.definitions
            )
            let stream = await client.stream(request: request)
            var content = ""
            var toolCalls: [OllamaToolCall] = []
            var receivedChunk = false

            for try await chunk in stream {
                try Task.checkCancellation()
                receivedChunk = true
                guard let message = chunk.message else { continue }
                if !message.content.isEmpty {
                    content.append(message.content)
                    continuation.yield(.assistantDelta(message.content))
                }
                if let calls = message.toolCalls, !calls.isEmpty {
                    toolCalls.append(contentsOf: calls)
                }
            }
            guard receivedChunk else { throw GemmaAgentRuntimeError.emptyResponse }
            let assistant = OllamaChatMessage(
                role: .assistant,
                content: content,
                toolCalls: toolCalls.isEmpty ? nil : toolCalls
            )
            runHistory.append(assistant)

            guard !toolCalls.isEmpty else {
                guard !content.isEmpty else { throw GemmaAgentRuntimeError.emptyResponse }
                history = Self.trimmedHistory(runHistory)
                continuation.yield(.completed)
                return
            }

            toolIterations += toolCalls.count
            guard toolIterations <= Self.maximumToolIterations else {
                throw GemmaAgentRuntimeError.toolLimitExceeded
            }
            for call in toolCalls {
                try Task.checkCancellation()
                guard WorkspaceToolName(rawValue: call.function.name) != nil else {
                    throw WorkspaceToolError.unknownTool(call.function.name)
                }
                let activityID = UUID()
                let detail = Self.activityDetail(for: call)
                continuation.yield(
                    .toolStarted(
                        GemmaToolActivity(id: activityID, name: call.function.name, detail: detail)
                    )
                )
                let result = try await tools.execute(call)
                try Task.checkCancellation()
                let boundedContent = String(result.content.prefix(Self.maximumToolResultCharacters))
                runHistory.append(
                    OllamaChatMessage(
                        role: .tool,
                        content: boundedContent,
                        toolName: call.function.name
                    )
                )
                continuation.yield(
                    .toolFinished(
                        GemmaToolActivity(
                            id: activityID,
                            name: call.function.name,
                            detail: result.truncated ? "\(detail) (bounded)" : detail,
                            referencedFiles: result.referencedFiles,
                            isComplete: true
                        )
                    )
                )
            }
            guard Self.historyCharacterCount(runHistory) <= Self.maximumHistoryCharacters else {
                throw GemmaAgentRuntimeError.transcriptLimitExceeded
            }
        }
    }

    private var historyCharacterCount: Int {
        Self.historyCharacterCount(history)
    }

    private nonisolated static func historyCharacterCount(_ messages: [OllamaChatMessage]) -> Int {
        messages.reduce(0) { partial, message in
            partial + message.content.count + (message.toolCalls?.count ?? 0) * 100
        }
    }

    private nonisolated static func trimmedHistory(
        _ messages: [OllamaChatMessage]
    ) -> [OllamaChatMessage] {
        guard historyCharacterCount(messages) > maximumHistoryCharacters / 2,
              let system = messages.first else {
            return messages
        }
        var turns: [[OllamaChatMessage]] = []
        for message in messages.dropFirst() {
            if message.role == .user || turns.isEmpty {
                turns.append([message])
            } else {
                turns[turns.count - 1].append(message)
            }
        }
        while turns.count > 1,
              historyCharacterCount([system] + turns.flatMap { $0 }) > maximumHistoryCharacters / 2 {
            turns.removeFirst()
        }
        return [system] + turns.flatMap { $0 }
    }

    private func cancelActiveTask() {
        activeTask?.cancel()
        activeTask = nil
    }

    private nonisolated static func activityDetail(for call: OllamaToolCall) -> String {
        let arguments = call.function.arguments
        switch WorkspaceToolName(rawValue: call.function.name) {
        case .searchWorkspace:
            if case .string(let query) = arguments["query"] { return "Search: \(query.prefix(80))" }
        case .readFile:
            if case .string(let path) = arguments["path"] { return "Read: \(path.prefix(120))" }
        case .readGitDiff:
            return "Inspect Git diff"
        case .readTerminalOutput:
            if case .number(let lines) = arguments["lines"] {
                return "Read terminal output: \(Int(lines)) lines"
            }
            return "Read terminal output"
        case nil:
            break
        }
        return call.function.name
    }
}
