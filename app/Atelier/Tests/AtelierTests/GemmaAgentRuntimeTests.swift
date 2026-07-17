import Foundation
import Testing
@testable import Atelier

@Suite("Gemma agent runtime")
struct GemmaAgentRuntimeTests {
    @Test("Executes tool calls in order and retains tool history")
    func toolSequence() async throws {
        let search = call(.searchWorkspace, ["query": .string("WorkspaceSession")])
        let read = call(.readFile, ["path": .string("WorkspaceSession.swift")])
        let client = ScriptedOllamaClient(responses: [
            .chunks([chunk(toolCalls: [search])]),
            .chunks([chunk(toolCalls: [read])]),
            .chunks([chunk(content: "Final answer")])
        ])
        let tools = RecordingWorkspaceTools()
        let runtime = GemmaAgentRuntime(client: client, tools: tools)

        let events = await runtime.events(for: "Explain cleanup")
        var received: [GemmaAgentEvent] = []
        for try await event in events { received.append(event) }

        #expect(received.contains(.assistantDelta("Final answer")))
        #expect(received.last == .completed)
        #expect(await tools.names == ["search_workspace", "read_file"])
        let requests = await client.requests
        #expect(requests.count == 3)
        #expect(requests[1].messages.contains { $0.toolCalls == [search] })
        #expect(requests[1].messages.contains { $0.role == .tool && $0.toolName == "search_workspace" })
    }

    @Test("Stops repeated calls at the configured limit")
    func toolLimit() async {
        let calls = (0..<9).map { index in
            call(.searchWorkspace, ["query": .string("query-\(index)")])
        }
        let client = ScriptedOllamaClient(responses: [.chunks([chunk(toolCalls: calls)])])
        let tools = RecordingWorkspaceTools()
        let runtime = GemmaAgentRuntime(client: client, tools: tools)
        let events = await runtime.events(for: "Loop")

        await #expect(throws: GemmaAgentRuntimeError.toolLimitExceeded) {
            for try await _ in events {}
        }
        #expect(await tools.names.isEmpty)
    }

    @Test("Rejects unknown tools before dispatch")
    func unknownTool() async {
        let unknown = OllamaToolCall(
            function: OllamaFunctionCall(name: "run_shell", arguments: [:])
        )
        let client = ScriptedOllamaClient(responses: [.chunks([chunk(toolCalls: [unknown])])])
        let tools = RecordingWorkspaceTools()
        let runtime = GemmaAgentRuntime(client: client, tools: tools)
        let events = await runtime.events(for: "Do something")

        await #expect(throws: WorkspaceToolError.unknownTool("run_shell")) {
            for try await _ in events {}
        }
    }

    @Test("Cancellation stops transport and tool work")
    func cancellation() async throws {
        let transport = ScriptedOllamaClient(responses: [.waiting])
        let tools = RecordingWorkspaceTools()
        let runtime = GemmaAgentRuntime(client: transport, tools: tools)
        let transportEvents = await runtime.events(for: "Wait")
        let transportConsumer = Task {
            do {
                for try await _ in transportEvents {}
                return false
            } catch { return true }
        }
        await Task.yield()
        await runtime.cancel()
        #expect(await transportConsumer.value)
        #expect(await transport.cancelCount > 0)

        let toolCall = call(.readFile, ["path": .string("file.swift")])
        let toolClient = ScriptedOllamaClient(responses: [.chunks([chunk(toolCalls: [toolCall])])])
        let waitingTools = RecordingWorkspaceTools(waitForCancellation: true)
        let toolRuntime = GemmaAgentRuntime(client: toolClient, tools: waitingTools)
        let toolEvents = await toolRuntime.events(for: "Read")
        let toolConsumer = Task {
            do {
                for try await _ in toolEvents {}
                return false
            } catch { return true }
        }
        while await waitingTools.names.isEmpty { await Task.yield() }
        await toolRuntime.cancel()
        #expect(await toolConsumer.value)
    }

    @Test("Failed turn is not retained in the next request")
    func failureDoesNotMutateHistory() async throws {
        let unknown = OllamaToolCall(
            function: OllamaFunctionCall(name: "run_shell", arguments: [:])
        )
        let client = ScriptedOllamaClient(responses: [
            .chunks([chunk(toolCalls: [unknown])]),
            .chunks([chunk(content: "Recovered")])
        ])
        let runtime = GemmaAgentRuntime(client: client, tools: RecordingWorkspaceTools())

        let failed = await runtime.events(for: "Unsafe first prompt")
        await #expect(throws: WorkspaceToolError.unknownTool("run_shell")) {
            for try await _ in failed {}
        }
        let recovered = await runtime.events(for: "Safe second prompt")
        for try await _ in recovered {}

        let requests = await client.requests
        #expect(requests.count == 2)
        #expect(requests[1].messages.map(\.role) == [.system, .user])
        #expect(requests[1].messages.last?.content == "Safe second prompt")
        #expect(!requests[1].messages.contains { $0.content == "Unsafe first prompt" })
        #expect(!requests[1].messages.contains { $0.toolCalls == [unknown] })
    }

    @Test("Cancelled tool turn is not retained in the next request")
    func cancellationDoesNotMutateHistory() async throws {
        let read = call(.readFile, ["path": .string("file.swift")])
        let client = ScriptedOllamaClient(responses: [
            .chunks([chunk(toolCalls: [read])]),
            .chunks([chunk(content: "Fresh answer")])
        ])
        let tools = RecordingWorkspaceTools(waitForCancellation: true)
        let runtime = GemmaAgentRuntime(client: client, tools: tools)
        let cancelled = await runtime.events(for: "Cancelled prompt")
        let consumer = Task {
            do {
                for try await _ in cancelled {}
                return false
            } catch {
                return true
            }
        }
        while await tools.names.isEmpty { await Task.yield() }
        await runtime.cancel()
        #expect(await consumer.value)

        let recovered = await runtime.events(for: "Prompt after cancellation")
        for try await _ in recovered {}

        let requests = await client.requests
        #expect(requests.count == 2)
        #expect(requests[1].messages.map(\.role) == [.system, .user])
        #expect(requests[1].messages.last?.content == "Prompt after cancellation")
        #expect(!requests[1].messages.contains { $0.content == "Cancelled prompt" })
        #expect(!requests[1].messages.contains { $0.toolCalls == [read] })
    }

    private func call(
        _ name: WorkspaceToolName,
        _ arguments: [String: OllamaJSONValue]
    ) -> OllamaToolCall {
        OllamaToolCall(function: OllamaFunctionCall(name: name.rawValue, arguments: arguments))
    }

    private func chunk(
        content: String = "",
        toolCalls: [OllamaToolCall]? = nil
    ) -> OllamaChatChunk {
        OllamaChatChunk(
            message: OllamaChatMessage(
                role: .assistant,
                content: content,
                toolCalls: toolCalls
            ),
            done: true
        )
    }
}

nonisolated enum ScriptedResponse: Sendable {
    case chunks([OllamaChatChunk])
    case failure(OllamaCloudError)
    case waiting
}

actor ScriptedOllamaClient: OllamaChatStreaming {
    private var responses: [ScriptedResponse]
    private(set) var requests: [OllamaChatRequest] = []
    private(set) var cancelCount = 0

    init(responses: [ScriptedResponse]) {
        self.responses = responses
    }

    func stream(request: OllamaChatRequest) -> AsyncThrowingStream<OllamaChatChunk, Error> {
        requests.append(request)
        let response = responses.isEmpty ? .chunks([]) : responses.removeFirst()
        return AsyncThrowingStream { continuation in
            switch response {
            case .chunks(let chunks):
                for chunk in chunks { continuation.yield(chunk) }
                continuation.finish()
            case .failure(let error):
                continuation.finish(throwing: error)
            case .waiting:
                continuation.onTermination = { @Sendable _ in }
            }
        }
    }

    func cancel() {
        cancelCount += 1
    }
}

actor RecordingWorkspaceTools: WorkspaceToolExecuting {
    private(set) var names: [String] = []
    private let waitForCancellation: Bool

    init(waitForCancellation: Bool = false) {
        self.waitForCancellation = waitForCancellation
    }

    func execute(_ call: OllamaToolCall) async throws -> WorkspaceToolResult {
        names.append(call.function.name)
        if waitForCancellation {
            try await Task.sleep(for: .seconds(60))
        }
        return WorkspaceToolResult(
            content: "tool result for \(call.function.name)",
            referencedFiles: ["file.swift"]
        )
    }
}
