import Foundation
import Testing
@testable import Atelier

@Suite("Gemma agent presentation")
@MainActor
struct GemmaAgentModelTests {
    @Test("One workspace opens one Gemma tab")
    func oneSessionIdentity() {
        let root = temporaryDirectory()
        let model = makeModel(responses: [.chunks([finalChunk("Ready")])])
        let tabs = TerminalTabsModel(workspacePath: root.path)
        defer { tabs.closeAll() }

        tabs.openGemma(model)
        let firstSelection = tabs.selectedID
        tabs.openGemma(model)

        #expect(tabs.gemmaTabCount == 1)
        #expect(tabs.selectedID == firstSelection)
    }

    @Test("Model streams an answer and clears its session")
    func presentationLifecycle() async {
        let model = makeModel(responses: [.chunks([finalChunk("Hello workspace")])])
        model.send("Hello")
        await waitUntil { model.status != .running }

        #expect(model.status == .completed)
        #expect(model.messages.last?.content == "Hello workspace")
        model.clear()
        #expect(model.status == .idle)
        #expect(model.messages.isEmpty)
    }

    @Test("Workspace cleanup cancels its active Gemma run")
    func workspaceCleanup() async {
        let root = temporaryDirectory()
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let model = makeModel(responses: [.waiting])
        let state = WorkspaceState(path: root.path, bookmark: nil, lastOpenedAt: .now)
        let session = WorkspaceSession(state: state, rootURL: root, gemmaAgent: model)
        defer { session.stop() }
        session.start()
        session.openGemma()
        model.send("Wait")
        #expect(model.isRunning)

        session.stop()

        #expect(!model.isRunning)
        #expect(session.terminalTabs.gemmaTabCount == 0)
    }

    @Test("Model exposes guidance only for detected Ollama failures")
    func failureGuidance() async {
        let authentication = makeModel(
            responses: [.failure(.httpStatus(401, "unauthorized"))]
        )
        authentication.send("Authenticate")
        await waitUntil { authentication.status != .running }
        #expect(authentication.recoverySuggestion == "Run `ollama signin`, then try again.")

        let unrelated = makeModel(responses: [.failure(.remote("service overloaded"))])
        unrelated.send("Retry")
        await waitUntil { unrelated.status != .running }
        #expect(unrelated.recoverySuggestion == nil)
    }

    private func makeModel(responses: [ScriptedResponse]) -> GemmaAgentModel {
        GemmaAgentModel(
            runtime: GemmaAgentRuntime(
                client: ScriptedOllamaClient(responses: responses),
                tools: RecordingWorkspaceTools()
            )
        )
    }

    private func finalChunk(_ text: String) -> OllamaChatChunk {
        OllamaChatChunk(
            message: OllamaChatMessage(role: .assistant, content: text),
            done: true
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("atelier-agent-model-\(UUID().uuidString)", isDirectory: true)
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<1_000 {
            if condition() { return }
            await Task.yield()
        }
    }
}
