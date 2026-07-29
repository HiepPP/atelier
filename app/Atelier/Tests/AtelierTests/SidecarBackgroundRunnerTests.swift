import Foundation
import Testing
@testable import Atelier

@Suite("Sidecar run handoff")
struct SidecarRunHandoffTests {
    @Test("Abandon unparks a parked waiter even though no result ever arrives")
    func abandonUnparksWithoutResult() async {
        let handoff = SidecarRunHandoff()
        let waiter = Task {
            try await withCheckedThrowingContinuation { handoff.attach($0) }
        }
        await Task.yield()
        handoff.abandon()
        await #expect(throws: CancellationError.self) { try await waiter.value }
        // A late result from the wedged work is dropped without effect.
        handoff.finish(.success("late"))
    }

    @Test("A result delivered before attach resumes the waiter immediately")
    func finishBeforeAttach() async throws {
        let handoff = SidecarRunHandoff()
        handoff.finish(.success("done"))
        let value = try await withCheckedThrowingContinuation { handoff.attach($0) }
        #expect(value == "done")
    }

    @Test("Abandon before attach fails the waiter immediately")
    func abandonBeforeAttach() async {
        let handoff = SidecarRunHandoff()
        handoff.abandon()
        await #expect(throws: CancellationError.self) {
            try await withCheckedThrowingContinuation { handoff.attach($0) }
        }
    }
}

@Suite("Sidecar background runner")
struct SidecarBackgroundRunnerTests {
    private func chunk(content: String) -> OllamaChatChunk {
        OllamaChatChunk(
            message: OllamaChatMessage(role: .assistant, content: content, toolCalls: nil),
            done: true
        )
    }

    private func makeRunner(
        responses: [ScriptedResponse]
    ) -> (runner: SidecarBackgroundRunner, client: ScriptedOllamaClient) {
        let client = ScriptedOllamaClient(responses: responses)
        let runner = SidecarBackgroundRunner(
            runtime: GemmaAgentRuntime(client: client, tools: RecordingWorkspaceTools())
        )
        return (runner, client)
    }

    @Test("cancelAll unparks a never-completing run and the next run proceeds")
    func cancelAllUnparksAndNextRunProceeds() async throws {
        let (runner, client) = makeRunner(
            responses: [.waiting, .chunks([chunk(content: "ok")])]
        )
        let first = Task { try await runner.run(prompt: "first") }
        while await client.requests.isEmpty { await Task.yield() }

        await runner.cancelAll()
        await #expect(throws: (any Error).self) { try await first.value }

        let text = try await runner.run(prompt: "second")
        #expect(text == "ok")
    }

    @Test("A new run preempts a parked run instead of waiting behind it")
    func preemptionUnparksPreviousCaller() async throws {
        let (runner, client) = makeRunner(
            responses: [.waiting, .chunks([chunk(content: "second")])]
        )
        let first = Task { try await runner.run(prompt: "first") }
        while await client.requests.isEmpty { await Task.yield() }

        let text = try await runner.run(prompt: "second")
        #expect(text == "second")
        await #expect(throws: (any Error).self) { try await first.value }
    }

    @Test("Cancelling the caller unparks it without waiting for the work")
    func callerCancellationAbandonsWait() async {
        let (runner, client) = makeRunner(responses: [.waiting])
        let caller = Task { try await runner.run(prompt: "wedged") }
        while await client.requests.isEmpty { await Task.yield() }

        caller.cancel()
        await #expect(throws: (any Error).self) { try await caller.value }
    }
}
