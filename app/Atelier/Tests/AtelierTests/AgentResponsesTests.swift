import AppKit
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
        let moved = AgentTranscriptParser.extractAll(
            from: codex,
            workspacePath: "/tmp/project",
            sourceID: "moved-codex.jsonl",
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
        #expect(codexResponses.map(\.id) == moved.map(\.id))
        #expect(claudeResponses.count == 1)
        #expect(claudeResponses.first?.provider == .claude)
        #expect(claudeResponses.first?.sessionID == "claude-session")
    }

    @Test("Missing session and record IDs use deterministic provider-scoped fallbacks")
    func deterministicFallbackIdentity() {
        let codex = """
        {"timestamp":"2026-07-17T08:00:00.000Z","type":"session_meta","payload":{"cwd":"/tmp/project"}}
        {"timestamp":"2026-07-17T08:00:02.000Z","type":"response_item","payload":{"type":"message","role":"assistant","phase":"final_answer","content":[{"type":"output_text","text":"Done"}]}}
        """
        let first = AgentTranscriptParser.extractAll(
            from: codex,
            workspacePath: "/tmp/project",
            sourceID: "/tmp/transcripts/session.jsonl",
            modifiedAfter: .distantPast
        )
        let second = AgentTranscriptParser.extractAll(
            from: codex,
            workspacePath: "/tmp/project",
            sourceID: "/tmp/transcripts/session.jsonl",
            modifiedAfter: .distantPast
        )
        let codexFallback = AgentTranscriptParser.fallbackSessionID(
            provider: .codex,
            workspacePath: "/tmp/project",
            sourceID: "/tmp/transcripts/session.jsonl"
        )
        let claudeFallback = AgentTranscriptParser.fallbackSessionID(
            provider: .claude,
            workspacePath: "/tmp/project",
            sourceID: "/tmp/transcripts/session.jsonl"
        )

        #expect(first.count == 1)
        #expect(first.map(\.id) == second.map(\.id))
        #expect(first.first?.sessionID == codexFallback)
        #expect(codexFallback.hasPrefix("local-"))
        #expect(codexFallback != claudeFallback)
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

    @Test("Monitor parses only appended transcript bytes")
    func incrementalTranscriptMonitor() async throws {
        let root = temporaryDirectory("incremental-monitor")
        let workspace = root.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let transcriptURL = root.appendingPathComponent("session.jsonl")
        let initial = """
        {"timestamp":"2026-07-17T08:00:00.000Z","type":"session_meta","payload":{"id":"one","cwd":"\(workspace.path)"}}
        {"timestamp":"2026-07-17T08:00:01.000Z","type":"response_item","payload":{"id":"first","type":"message","role":"assistant","phase":"final_answer","content":[{"type":"output_text","text":"One"}]}}
        """
        try initial.write(to: transcriptURL, atomically: true, encoding: .utf8)
        let monitor = AgentTranscriptMonitor(
            workspacePath: workspace.path,
            modifiedAfter: .distantPast,
            roots: [root]
        )

        let first = await monitor.loadResponses()
        let initialParsedBytes = await monitor.parsedByteCount
        #expect(first.map(\.markdown) == ["One"])

        let appended = Data("""

        {"timestamp":"2026-07-17T08:00:02.000Z","type":"response_item","payload":{"id":"second","type":"message","role":"assistant","phase":"final_answer","content":[{"type":"output_text","text":"Two"}]}}
        """.utf8)
        let midpoint = appended.count / 2
        let handle = try FileHandle(forWritingTo: transcriptURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: appended.prefix(midpoint))

        let partial = await monitor.loadResponses()
        #expect(partial.map(\.markdown) == ["One"])

        try handle.write(contentsOf: appended.suffix(from: midpoint))
        let complete = await monitor.loadResponses()
        let parsedBytesAfterAppend = await monitor.parsedByteCount
        #expect(complete.map(\.markdown) == ["One", "Two"])
        #expect(parsedBytesAfterAppend - initialParsedBytes == appended.count)

        _ = await monitor.loadResponses()
        #expect(await monitor.parsedByteCount == parsedBytesAfterAppend)

        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: 10)],
            ofItemAtPath: transcriptURL.path
        )
        _ = await monitor.loadResponses()
        #expect(await monitor.parsedByteCount == parsedBytesAfterAppend)
    }

    @Test("Model deduplicates refreshes and exposes stable sessions")
    func modelAndSessionIdentity() async {
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
        #expect(model.sessions == [response.session])
        #expect(model.selectedSession == response.session)
        #expect(model.sessionSummaries == [
            AgentSessionSummary(
                session: response.session,
                latestResponseTime: response.timestamp,
                responseCount: 1,
                unreadCount: 1
            )
        ])
    }

    @Test("Session selection stays stable and read state is scoped to visible responses")
    func sessionSelectionAndReadState() async {
        let codexFirst = response(
            id: "same-record",
            provider: .codex,
            sessionID: "shared",
            time: 1,
            markdown: "Codex one"
        )
        let claude = response(
            id: "same-record",
            provider: .claude,
            sessionID: "shared",
            time: 2,
            markdown: "Claude one"
        )
        let codexSecond = response(
            id: "second",
            provider: .codex,
            sessionID: "shared",
            time: 3,
            markdown: "Codex two"
        )
        let source = SequencedAgentResponseSource([
            [codexFirst, claude],
            [codexFirst, claude, codexSecond]
        ])
        let model = AgentResponsesModel(source: source)

        await model.refresh()
        #expect(model.responses.count == 2)
        #expect(model.selectedSession == claude.session)
        #expect(model.unreadCount == 2)

        model.markRead(model.selectedResponses)
        #expect(model.unreadCount == 1)
        #expect(model.sessionSummaries.first(where: { $0.session == claude.session })?.unreadCount == 0)
        #expect(model.sessionSummaries.first(where: { $0.session == codexFirst.session })?.unreadCount == 1)

        model.selectSession(codexFirst.session)
        await model.refresh()
        #expect(model.selectedSession == codexFirst.session)
        #expect(model.selectedResponses.map(\.markdown) == ["Codex one", "Codex two"])
        #expect(model.sessionSummaries.first?.session == codexFirst.session)
        #expect(model.sessionSummaries.first?.responseCount == 2)
        #expect(model.unreadCount == 2)

        model.markRead(model.selectedResponses.prefix(1))
        #expect(model.unreadCount == 1)
        #expect(model.sessionSummaries.first(where: { $0.session == codexFirst.session })?.unreadCount == 1)
    }

    @Test("Opening preview does not clear hidden session unread state")
    func previewOpenPreservesUnreadState() async {
        let codex = response(id: "one", provider: .codex, sessionID: "codex", time: 1)
        let claude = response(id: "two", provider: .claude, sessionID: "claude", time: 2)
        let responses = AgentResponsesModel(source: StaticAgentResponseSource([codex, claude]))
        await responses.refresh()

        let root = temporaryDirectory("read-state")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let session = WorkspaceSession(
            state: WorkspaceState(path: root.path, bookmark: nil, lastOpenedAt: .now),
            rootURL: root,
            agentResponses: responses
        )
        session.openResponses()

        #expect(session.isAgentPreviewPresented)
        #expect(responses.unreadCount == 2)
        responses.markRead(responses.selectedResponses)
        #expect(responses.unreadCount == 1)
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

    @Test("Markdown parses tables without changing surrounding block order")
    func markdownTableBlocks() {
        let markdown = """
        Before.

        | Provider | State |
        | :--- | ---: |
        | Codex | Ready |
        | Claude | Working |

        After.
        """

        #expect(AgentMarkdownBlock.parse(markdown) == [
            .paragraph("Before."),
            .table(
                headers: ["Provider", "State"],
                rows: [["Codex", "Ready"], ["Claude", "Working"]]
            ),
            .paragraph("After.")
        ])
    }

    @Test("Markdown handles malformed fences and deterministic table row widths")
    func markdownEdgeCases() {
        let markdown = """
        | A | B |
        | --- | --- |
        | one |
        | two | three | ignored |

        > Quote

        ```swift
        let value = "unterminated"
        """

        #expect(AgentMarkdownBlock.parse(markdown) == [
            .table(headers: ["A", "B"], rows: [["one", ""], ["two", "three"]]),
            .quote("Quote"),
            .code(language: "swift", content: "let value = \"unterminated\"")
        ])

        let stopped = """
        | A | B |
        | --- | --- |
        | one | two |

        After | table
        """
        #expect(AgentMarkdownBlock.parse(stopped) == [
            .table(headers: ["A", "B"], rows: [["one", "two"]]),
            .paragraph("After | table")
        ])
    }

    @Test("Bounded code display keeps complete copy source")
    func codeCopyPolicy() {
        let source = String(repeating: "x", count: AgentCodeBlockPolicy.displayLimit + 25)
        #expect(AgentCodeBlockPolicy.displayedContent(source).hasSuffix("\n..."))
        #expect(AgentCodeBlockPolicy.displayedContent(source).count < source.count)
        #expect(AgentCodeBlockPolicy.copiedContent(source) == source)
    }

    @Test("New response affordance only appears away from bottom")
    func pendingResponsePolicy() {
        let old = AgentResponseReadIdentity(
            session: AgentSessionIdentity(provider: .codex, sessionID: "one"),
            responseID: "old"
        )
        let new = AgentResponseReadIdentity(session: old.session, responseID: "new")
        #expect(AgentResponseTimelinePolicy.showsPendingResponse(
            previousLastID: old,
            newLastID: new,
            isPinnedToBottom: false
        ))
        #expect(!AgentResponseTimelinePolicy.showsPendingResponse(
            previousLastID: old,
            newLastID: new,
            isPinnedToBottom: true
        ))
        #expect(!AgentResponseTimelinePolicy.showsPendingResponse(
            previousLastID: old,
            newLastID: old,
            isPinnedToBottom: false
        ))
    }

    @Test("Preview layout docks wide and overlays narrow without replacing tabs")
    func previewLayoutPolicy() {
        #expect(AgentPreviewLayoutPolicy.layout(containerWidth: 1_000) == .overlay)
        #expect(AgentPreviewLayoutPolicy.layout(containerWidth: 1_600) == .docked)
        #expect(AgentPreviewLayoutPolicy.panelWidth(
            containerWidth: 1_000,
            layout: .overlay
        ) == 460)
        #expect(AgentPreviewLayoutPolicy.panelWidth(
            containerWidth: 1_600,
            layout: .docked
        ) == 448)
        #expect(AgentPreviewLayoutPolicy.clampedDockedWidth(
            200,
            containerWidth: 1_600
        ) == 360)
        #expect(AgentPreviewLayoutPolicy.clampedDockedWidth(
            900,
            containerWidth: 1_600
        ) == 640)
        #expect(AgentPreviewLayoutPolicy.clampedDockedWidth(
            640,
            containerWidth: 1_000
        ) == 380)
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
        #expect(session.isAgentPreviewPresented)
        #expect(session.terminalTabs.terminalCount == 1)

        session.stop()
        #expect(!responses.isMonitoring)
        #expect(session.terminalTabs.terminalCount == 0)
    }

    @Test("Mermaid renderer produces PNG data")
    func mermaidRenderer() async throws {
        let data = try await MermaidImageRenderer().render(
            source: "flowchart LR\nA --> B",
            width: 480
        )

        #expect(Array(data.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10])
    }

    @Test("Mermaid width buckets avoid resize churn")
    func mermaidWidthBuckets() {
        #expect(MermaidRenderingPolicy.widthBucket(containerWidth: 300) == 480)
        #expect(MermaidRenderingPolicy.widthBucket(containerWidth: 600) == 720)
        #expect(MermaidRenderingPolicy.widthBucket(containerWidth: 800) == 720)
        #expect(MermaidRenderingPolicy.widthBucket(containerWidth: 1_600) == 960)
    }

    @Test("Mermaid image cache stays bounded")
    func mermaidCacheBound() async throws {
        let cache = MermaidImageCache(capacity: 2)
        _ = try await cache.image(source: "flowchart LR\nA --> B", width: 480)
        _ = try await cache.image(source: "flowchart LR\nB --> C", width: 480)
        _ = try await cache.image(source: "flowchart LR\nC --> D", width: 480)
        #expect(cache.entryCount == 2)

        _ = try await cache.image(source: "flowchart LR\nC --> D", width: 480)
        #expect(cache.entryCount == 2)
    }

    @Test("Mermaid cache reuses one renderer and cached image")
    func mermaidCacheReuse() async throws {
        let renderer = TestMermaidRenderer()
        let cache = MermaidImageCache(capacity: 2, renderer: renderer)

        _ = try await cache.image(source: "flowchart LR\nA --> B", width: 480)
        _ = try await cache.image(source: "flowchart LR\nA --> B", width: 480)

        #expect(renderer.callCount == 1)
        #expect(cache.entryCount == 1)
        #expect(cache.inFlightCount == 0)
    }

    @Test("Removing Mermaid cache cancels and clears in-flight work")
    func mermaidCacheCancellation() async {
        let renderer = TestMermaidRenderer(suspends: true)
        var starts = renderer.started.makeAsyncIterator()
        let cache = MermaidImageCache(capacity: 2, renderer: renderer)
        let request = Task {
            try await cache.image(source: "flowchart LR\nA --> B", width: 480)
        }

        _ = await starts.next()
        #expect(cache.inFlightCount == 1)
        cache.removeAll()
        let result = await request.result

        #expect(cache.inFlightCount == 0)
        #expect(cache.entryCount == 0)
        if case .success = result {
            Issue.record("Expected canceled Mermaid render to fail")
        }
    }

    @Test("Invalid Mermaid source activates selectable source fallback")
    func mermaidInvalidSourceFallback() async {
        let renderer = TestMermaidRenderer(rejectsSource: "not mermaid")
        let cache = MermaidImageCache(renderer: renderer)
        var hasRenderError = false
        do {
            _ = try await cache.image(source: "not mermaid", width: 480)
        } catch {
            hasRenderError = true
        }

        #expect(hasRenderError)
        #expect(MermaidResponsePresentationPolicy.showsSource(
            userRequested: false,
            hasRenderError: hasRenderError
        ))
    }

    private func response(
        id: String,
        provider: AgentProvider,
        sessionID: String,
        time: TimeInterval,
        markdown: String = "Ready"
    ) -> AgentResponse {
        AgentResponse(
            id: id,
            provider: provider,
            sessionID: sessionID,
            timestamp: Date(timeIntervalSince1970: time),
            markdown: markdown
        )
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

nonisolated actor SequencedAgentResponseSource: AgentResponseSource {
    private let snapshots: [[AgentResponse]]
    private var index = 0

    init(_ snapshots: [[AgentResponse]]) {
        self.snapshots = snapshots
    }

    func loadResponses() async -> [AgentResponse] {
        guard !snapshots.isEmpty else { return [] }
        let snapshot = snapshots[min(index, snapshots.count - 1)]
        index += 1
        return snapshot
    }
}

@MainActor
private final class TestMermaidRenderer: MermaidImageRendering {
    private let suspends: Bool
    private let rejectedSource: String?
    private let startedContinuation: AsyncStream<Void>.Continuation
    let started: AsyncStream<Void>
    private(set) var callCount = 0

    init(suspends: Bool = false, rejectsSource: String? = nil) {
        self.suspends = suspends
        rejectedSource = rejectsSource
        var continuation: AsyncStream<Void>.Continuation!
        started = AsyncStream { continuation = $0 }
        startedContinuation = continuation
    }

    func render(source: String, width: CGFloat) async throws -> Data {
        callCount += 1
        startedContinuation.yield()
        if source == rejectedSource {
            throw MermaidImageRendererError.invalidResult
        }
        if suspends {
            try await Task.sleep(for: .seconds(60))
        }
        return Self.pngData()
    }

    private static func pngData() -> Data {
        Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        )!
    }
}
