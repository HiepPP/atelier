import Foundation
import Testing
@testable import Atelier

@Suite("Native agent responses")
@MainActor
struct AgentResponsesTests {
    @Test("Codex and Claude final answers keep stable identities")
    func parsesProvidersAndStableIDs() {
        let codex = #"""
        {"timestamp":"2026-07-17T08:00:00.000Z","type":"session_meta","payload":{"id":"codex-session","cwd":"/tmp/project"}}
        {"timestamp":"2026-07-17T08:00:01.000Z","type":"response_item","payload":{"type":"message","role":"assistant","phase":"commentary","content":[{"type":"output_text","text":"Working"}]}}
        {"timestamp":"2026-07-17T08:00:02.000Z","type":"response_item","payload":{"type":"message","role":"assistant","phase":"final_answer","content":[{"type":"output_text","text":"# Done\n\n```mermaid\ngraph TD\nA --> B\n```"}]}}
        """#
        let claude = """
        {"uuid":"tool","timestamp":"2026-07-17T08:00:01.000Z","type":"assistant","cwd":"/tmp/project","sessionId":"claude-session","message":{"role":"assistant","stop_reason":"tool_use","content":[{"type":"text","text":"Working"}]}}
        {"uuid":"final","timestamp":"2026-07-17T08:00:03.000Z","type":"assistant","cwd":"/tmp/project","sessionId":"claude-session","message":{"role":"assistant","stop_reason":"end_turn","content":[{"type":"text","text":"Claude done"}]}}
        """

        let codexResponses = AgentTranscriptParser.extractAll(
            from: codex,
            workspacePath: "/tmp/project",
            sourceID: "codex.jsonl",
            modifiedAfter: .distantPast
        )
        let repeated = AgentTranscriptParser.extractAll(
            from: codex,
            workspacePath: "/tmp/project",
            sourceID: "codex.jsonl",
            modifiedAfter: .distantPast
        )
        let claudeResponses = AgentTranscriptParser.extractAll(
            from: claude,
            workspacePath: "/tmp/project",
            sourceID: "claude.jsonl",
            modifiedAfter: .distantPast
        )

        #expect(codexResponses.count == 1)
        #expect(codexResponses.first?.provider == .codex)
        #expect(codexResponses.first?.sessionID == "codex-session")
        #expect(codexResponses.map(\.id) == repeated.map(\.id))
        #expect(claudeResponses.count == 1)
        #expect(claudeResponses.first?.provider == .claude)
        #expect(claudeResponses.first?.sessionID == "claude-session")
    }

    @Test("Monitor loads every matching transcript and deduplicates scans")
    func multiSessionMonitor() async throws {
        let root = temporaryDirectory("monitor")
        let transcriptRoot = root.appendingPathComponent("transcripts", isDirectory: true)
        try FileManager.default.createDirectory(at: transcriptRoot, withIntermediateDirectories: true)
        let workspace = root.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)

        let codex = """
        {"timestamp":"2026-07-17T08:00:00.000Z","type":"session_meta","payload":{"id":"one","cwd":"\(workspace.path)"}}
        {"timestamp":"2026-07-17T08:00:02.000Z","type":"response_item","payload":{"type":"message","role":"assistant","phase":"final_answer","content":[{"type":"output_text","text":"One"}]}}
        """
        let claude = """
        {"uuid":"two","timestamp":"2026-07-17T08:00:03.000Z","type":"assistant","cwd":"\(workspace.path)","sessionId":"two","message":{"role":"assistant","stop_reason":"end_turn","content":[{"type":"text","text":"Two"}]}}
        """
        let unrelated = """
        {"timestamp":"2026-07-17T08:00:00.000Z","type":"session_meta","payload":{"cwd":"/tmp/other"}}
        {"timestamp":"2026-07-17T08:00:04.000Z","type":"response_item","payload":{"type":"message","role":"assistant","phase":"final_answer","content":[{"type":"output_text","text":"Wrong"}]}}
        """
        try codex.write(to: transcriptRoot.appendingPathComponent("one.jsonl"), atomically: true, encoding: .utf8)
        try claude.write(to: transcriptRoot.appendingPathComponent("two.jsonl"), atomically: true, encoding: .utf8)
        try unrelated.write(to: transcriptRoot.appendingPathComponent("other.jsonl"), atomically: true, encoding: .utf8)

        let monitor = AgentTranscriptMonitor(
            workspacePath: workspace.path,
            modifiedAfter: .distantPast,
            roots: [transcriptRoot]
        )
        let first = await monitor.loadResponses()
        let second = await monitor.loadResponses()

        let appended = """
        {"timestamp":"2026-07-17T08:00:05.000Z","type":"response_item","payload":{"type":"message","role":"assistant","phase":"final_answer","content":[{"type":"output_text","text":"Three"}]}}
        """
        try (codex + "\n" + appended).write(
            to: transcriptRoot.appendingPathComponent("one.jsonl"),
            atomically: true,
            encoding: .utf8
        )
        let third = await monitor.loadResponses()

        #expect(first.map(\.markdown) == ["One", "Two"])
        #expect(first.map(\.id) == second.map(\.id))
        #expect(Set(first.map(\.id)).count == 2)
        #expect(third.map(\.markdown) == ["One", "Two", "Three"])
        #expect(Array(third.prefix(2)).map(\.id) == first.map(\.id))
    }

    @Test("Model deduplicates refreshes and one Responses tab is reused")
    func modelAndTabIdentity() async {
        let response = AgentResponse(
            id: "stable",
            provider: .codex,
            sessionID: "session",
            timestamp: Date(timeIntervalSince1970: 1),
            markdown: "Ready"
        )
        let model = AgentResponsesModel(source: StaticAgentResponseSource([response]))
        await model.refresh()
        await model.refresh()

        #expect(model.responses == [response])
        #expect(model.unreadCount == 1)

        let tabs = TerminalTabsModel(workspacePath: temporaryDirectory("tabs").path)
        defer { tabs.closeAll() }
        tabs.openResponses(model)
        let selectedID = tabs.selectedID
        tabs.openResponses(model)

        #expect(tabs.responsesTabCount == 1)
        #expect(tabs.selectedID == selectedID)
        #expect(model.unreadCount == 0)
    }

    @Test("Markdown preserves block order and Mermaid source fallback")
    func markdownBlocks() {
        let markdown = """
        # Result

        Before.

        ```mermaid
        flowchart LR
        A --> B
        ```

        ```swift
        let value = 1
        ```
        """

        #expect(AgentMarkdownBlock.parse(markdown) == [
            .heading(level: 1, content: "Result"),
            .paragraph("Before."),
            .mermaid("flowchart LR\nA --> B"),
            .code(language: "swift", content: "let value = 1")
        ])
    }

    @Test("Workspace owns and stops response monitoring")
    func workspaceLifecycle() {
        let root = temporaryDirectory("workspace")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let state = WorkspaceState(path: root.path, bookmark: nil, lastOpenedAt: .now)
        let responses = AgentResponsesModel(source: StaticAgentResponseSource([]))
        let session = WorkspaceSession(
            state: state,
            rootURL: root,
            agentResponses: responses
        )

        session.start()
        session.openResponses()
        #expect(responses.isMonitoring)
        #expect(session.terminalTabs.responsesTabCount == 1)

        session.stop()
        #expect(!responses.isMonitoring)
        #expect(session.terminalTabs.responsesTabCount == 0)
    }

    @Test("Mermaid renderer produces PNG data")
    func mermaidRenderer() async throws {
        let data = try await MermaidImageRenderer().render(
            source: "flowchart LR\nA --> B",
            width: 480
        )

        #expect(Array(data.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10])
    }

    private func temporaryDirectory(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("atelier-responses-\(name)-\(UUID().uuidString)", isDirectory: true)
    }
}

nonisolated actor StaticAgentResponseSource: AgentResponseSource {
    private let responses: [AgentResponse]

    init(_ responses: [AgentResponse]) {
        self.responses = responses
    }

    func loadResponses() async -> [AgentResponse] {
        responses
    }
}
