import AppKit
import Foundation
import SwiftUI
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

    @Test("Monitor restores only the newest 100 final responses")
    func monitorRestoreLimit() async throws {
        let root = temporaryDirectory("restore-limit")
        let transcriptRoot = root.appendingPathComponent("transcripts", isDirectory: true)
        try FileManager.default.createDirectory(at: transcriptRoot, withIntermediateDirectories: true)
        let workspace = root.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)

        var lines = [
            """
            {"timestamp":"2026-07-17T08:00:00.000Z","type":"session_meta","payload":{"id":"restored","cwd":"\(workspace.path)"}}
            """
        ]
        for index in 0..<120 {
            let minute = index / 60
            let second = index % 60
            lines.append(
                """
                {"timestamp":"2026-07-17T08:\(String(format: "%02d", minute)):\(String(format: "%02d", second)).000Z","type":"response_item","payload":{"id":"response-\(index)","type":"message","role":"assistant","phase":"final_answer","content":[{"type":"output_text","text":"Response \(index)"}]}}
                """
            )
        }
        try lines.joined(separator: "\n").write(
            to: transcriptRoot.appendingPathComponent("restored.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let monitor = AgentTranscriptMonitor(
            workspacePath: workspace.path,
            roots: [transcriptRoot]
        )
        let restored = await monitor.loadResponses()

        #expect(restored.count == 100)
        #expect(restored.first?.markdown == "Response 20")
        #expect(restored.last?.markdown == "Response 119")
    }

    @Test("Monitor parses only a bounded set of recent transcript files")
    func boundedTranscriptDiscovery() async throws {
        let root = temporaryDirectory("bounded-discovery")
        let transcriptRoot = root.appendingPathComponent("transcripts", isDirectory: true)
        try FileManager.default.createDirectory(at: transcriptRoot, withIntermediateDirectories: true)
        let workspace = root.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        var expectedParsedBytes = 0

        for index in 0..<4 {
            let dayRoot = transcriptRoot.appendingPathComponent(
                "2026-07-\(String(format: "%02d", index + 1))",
                isDirectory: true
            )
            try FileManager.default.createDirectory(at: dayRoot, withIntermediateDirectories: true)
            let transcript = """
            {"timestamp":"2026-07-17T08:00:00.000Z","type":"session_meta","payload":{"id":"session-\(index)","cwd":"\(workspace.path)"}}
            {"timestamp":"2026-07-17T08:00:0\(index).000Z","type":"response_item","payload":{"id":"response-\(index)","type":"message","role":"assistant","phase":"final_answer","content":[{"type":"output_text","text":"Response \(index)"}]}}
            """
            let url = dayRoot.appendingPathComponent("session-\(index).jsonl")
            try transcript.write(to: url, atomically: true, encoding: .utf8)
            let modificationDate = Date(timeIntervalSince1970: TimeInterval(index + 1))
            for path in [url.path, dayRoot.path] {
                try FileManager.default.setAttributes(
                    [.modificationDate: modificationDate],
                    ofItemAtPath: path
                )
            }
            if index >= 2 {
                expectedParsedBytes += transcript.utf8.count
            }
        }

        let monitor = AgentTranscriptMonitor(
            workspacePath: workspace.path,
            roots: [transcriptRoot],
            transcriptLimitPerRoot: 2
        )
        let restored = await monitor.loadResponses()

        #expect(restored.map(\.markdown) == ["Response 2", "Response 3"])
        #expect(await monitor.parsedByteCount == expectedParsedBytes)
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

    @Test("Relaunch restores existing responses as read, then tracks new responses as unread")
    func relaunchRestoreReadState() async {
        let restored = response(
            id: "restored",
            provider: .codex,
            sessionID: "session",
            time: 1,
            markdown: "Restored"
        )
        let live = response(
            id: "live",
            provider: .codex,
            sessionID: "session",
            time: 2,
            markdown: "Live"
        )
        let source = SequencedAgentResponseSource([
            [restored],
            [restored, live]
        ])
        let relaunchedModel = AgentResponsesModel(source: source)

        relaunchedModel.start()
        for _ in 0..<100 {
            if !relaunchedModel.responses.isEmpty { break }
            await Task.yield()
        }

        #expect(relaunchedModel.responses == [restored])
        #expect(relaunchedModel.unreadCount == 0)

        await relaunchedModel.refresh()

        #expect(relaunchedModel.responses == [restored, live])
        #expect(relaunchedModel.unreadCount == 1)
        relaunchedModel.stop()
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

    @Test("Opening sidecar does not clear hidden session unread state")
    func sidecarOpenPreservesUnreadState() async {
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
        session.openAgentSidecar()

        #expect(session.isAgentSidecarPresented)
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

    @Test("Markdown distinguishes valid, empty, and unclosed Mermaid fences")
    func mermaidFenceStates() {
        let markdown = """
        ````MERMAID
        flowchart LR
        A --> B
        ````

        ```mermaid
        ```

        ~~~mermaid
        graph TD
        A --> B
        """

        #expect(AgentMarkdownBlock.parse(markdown) == [
            .mermaid("flowchart LR\nA --> B"),
            .invalidMermaid(
                source: "",
                error: "Mermaid block is empty. Source is shown below."
            ),
            .invalidMermaid(
                source: "graph TD\nA --> B",
                error: "Mermaid block is missing its closing fence. Source is shown below."
            )
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
                alignments: [.left, .right],
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
            .table(
                headers: ["A", "B"],
                alignments: [.left, .left],
                rows: [["one", ""], ["two", "three"]]
            ),
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
            .table(
                headers: ["A", "B"],
                alignments: [.left, .left],
                rows: [["one", "two"]]
            ),
            .paragraph("After | table")
        ])
    }

    @Test("Markdown distinguishes task lists from unordered lists")
    func markdownTaskLists() {
        let markdown = """
        - [ ] Pending
        - [x] Done
        * [X] Also done
        - Regular
        """

        #expect(AgentMarkdownBlock.parse(markdown) == [
            .taskItem(isCompleted: false, depth: 0, content: "Pending"),
            .taskItem(isCompleted: true, depth: 0, content: "Done"),
            .taskItem(isCompleted: true, depth: 0, content: "Also done"),
            .unorderedItem(depth: 0, content: "Regular")
        ])
    }

    @Test("Markdown joins wrapped list item and quote continuation lines")
    func markdownLazyContinuation() {
        let markdown = """
        - Outline clicks reveal the source heading line in Source mode
          and the rendered heading character range in Preview mode.
        - Second item
        1. Ordered item
           wrapped tail
        - [x] Task item
          wrapped tail

        Separate paragraph.
        """

        #expect(AgentMarkdownBlock.parse(markdown) == [
            .unorderedItem(
                depth: 0,
                content: "Outline clicks reveal the source heading line in Source mode "
                    + "and the rendered heading character range in Preview mode."
            ),
            .unorderedItem(depth: 0, content: "Second item"),
            .orderedItem(number: 1, depth: 0, content: "Ordered item wrapped tail"),
            .taskItem(
                isCompleted: true,
                depth: 0,
                content: "Task item wrapped tail"
            ),
            .paragraph("Separate paragraph.")
        ])

        let quoted = """
        > First quote line
        > second quote line
        lazy tail

        After.
        """
        #expect(AgentMarkdownBlock.parse(quoted) == [
            .quote("First quote line second quote line lazy tail"),
            .paragraph("After.")
        ])

        let interrupted = """
        - Item
        ## Heading
        Plain line
        """
        #expect(AgentMarkdownBlock.parse(interrupted) == [
            .unorderedItem(depth: 0, content: "Item"),
            .heading(level: 2, content: "Heading"),
            .paragraph("Plain line")
        ])
    }

    @Test("Markdown reads leading front matter as one metadata block")
    func markdownFrontMatter() {
        let markdown = """
        ---
        name: atelier-preview
        description: "Editorial Markdown surface"
        metadata:
          type: project
          tags:
            - macos
            - swiftui
        ---

        # Title

        Body.
        """

        #expect(AgentMarkdownBlock.parse(markdown) == [
            .frontMatter([
                MarkdownFrontMatterEntry(key: "name", value: "atelier-preview"),
                MarkdownFrontMatterEntry(
                    key: "description",
                    value: "Editorial Markdown surface"
                ),
                MarkdownFrontMatterEntry(
                    key: "metadata.type",
                    value: "project"
                ),
                MarkdownFrontMatterEntry(
                    key: "metadata.tags",
                    value: "macos, swiftui"
                )
            ]),
            .heading(level: 1, content: "Title"),
            .paragraph("Body.")
        ])
    }

    @Test("Markdown keeps dividers when leading front matter is not metadata")
    func markdownFrontMatterFallback() {
        let unclosed = """
        ---
        name: atelier
        """
        #expect(AgentMarkdownBlock.parse(unclosed) == [
            .divider,
            .paragraph("name: atelier")
        ])

        let prose = """
        ---
        Plain divider then prose.
        ---
        """
        #expect(AgentMarkdownBlock.parse(prose) == [
            .divider,
            .paragraph("Plain divider then prose."),
            .divider
        ])

        let midDocument = """
        # Title

        ---

        name: not front matter
        """
        #expect(AgentMarkdownBlock.parse(midDocument) == [
            .heading(level: 1, content: "Title"),
            .divider,
            .paragraph("name: not front matter")
        ])
    }

    @Test("Markdown document type policy marks only a leading H1 lede paragraph")
    func markdownLedePolicy() {
        let withLede: [AgentMarkdownBlock] = [
            .heading(level: 1, content: "Title"),
            .paragraph("Opening."),
            .paragraph("Second.")
        ]
        #expect(MarkdownDocumentTypePolicy.hasLedeParagraph(blocks: withLede))

        #expect(!MarkdownDocumentTypePolicy.hasLedeParagraph(blocks: [
            .heading(level: 2, content: "Section"),
            .paragraph("Opening.")
        ]))
        #expect(!MarkdownDocumentTypePolicy.hasLedeParagraph(blocks: [
            .heading(level: 1, content: "Title"),
            .unorderedItem(depth: 0, content: "Item")
        ]))
        #expect(!MarkdownDocumentTypePolicy.hasLedeParagraph(blocks: [
            .heading(level: 1, content: "Title")
        ]))
    }

    @Test("Markdown table cells wrap by character only for long unbroken tokens")
    func markdownTableCellWrapPolicy() {
        #expect(
            MarkdownTableCellPolicy.wrapsByCharacter(
                "app/Atelier/Sources/Atelier/Editor/FilePreview.swift"
            )
        )
        #expect(!MarkdownTableCellPolicy.wrapsByCharacter("Short cell value"))
        #expect(!MarkdownTableCellPolicy.wrapsByCharacter(""))
        #expect(
            !MarkdownTableCellPolicy.wrapsByCharacter(
                "many small words stay word wrapped in the column"
            )
        )
    }

    @Test("Native Markdown draws an H1 accent lead plus hairline across the measure")
    func nativeMarkdownHeadingRule() {
        let rendered = MarkdownAttributedDocumentBuilder.build(
            document: ParsedMarkdownDocument(source: "# Title"),
            scale: 1,
            displayScale: 2,
            usesDarkAppearance: false
        )
        #expect(
            (
                rendered.attributedString.attribute(
                    .atelierHeadingRule,
                    at: 0,
                    effectiveRange: nil
                ) as? NSNumber
            )?.intValue == 1
        )
        #expect(
            rendered.attributedString.attribute(
                .underlineStyle,
                at: 0,
                effectiveRange: nil
            ) == nil
        )

        let measure: CGFloat = 300
        let storage = NSTextStorage(attributedString: rendered.attributedString)
        let layoutManager = MarkdownPreviewLayoutManager(metrics: .current)
        storage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(
            containerSize: NSSize(width: measure, height: 200)
        )
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)
        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(for: textContainer)

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(measure),
            pixelsHigh: 200,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
            Issue.record("Expected a bitmap context for heading-rule rendering")
            return
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: measure, height: 200).fill()
        // Decorations only: glyphs stay unpainted so every opaque pixel is the rule.
        NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
            layoutManager.drawBackground(forGlyphRange: glyphRange, at: .zero)
        }
        graphics.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        var warm = NSRect.null
        var neutral = NSRect.null
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                // The hairline is a half-point fill, so it lands as a partial alpha row.
                guard let color = bitmap.colorAt(x: x, y: y)?
                    .usingColorSpace(.sRGB),
                      color.alphaComponent > 0.15 else {
                    continue
                }
                let pixel = NSRect(x: x, y: y, width: 1, height: 1)
                if color.redComponent - color.blueComponent > 0.2 {
                    warm = warm.union(pixel)
                } else {
                    neutral = neutral.union(pixel)
                }
            }
        }
        guard !warm.isNull, !neutral.isNull else {
            Issue.record("Expected an accent lead segment and a hairline")
            return
        }
        #expect(warm.minX <= 1)
        #expect(warm.maxX <= AtelierMetrics.space2XL + 1)
        #expect(neutral.minX >= warm.maxX - 1)
        #expect(neutral.maxX >= measure - 2)
        #expect(warm.height <= 2)
        #expect(neutral.height <= 2)
    }

    @Test("Native Markdown dims and strikes completed task items")
    func nativeMarkdownTaskItemStyling() {
        let rendered = MarkdownAttributedDocumentBuilder.build(
            document: ParsedMarkdownDocument(
                source: "- [x] Done\n- [ ] Open"
            ),
            scale: 1,
            displayScale: 2,
            usesDarkAppearance: false
        )
        let text = rendered.attributedString.string as NSString
        let doneRange = text.range(of: "Done")
        let openRange = text.range(of: "Open")
        #expect(doneRange.location != NSNotFound)
        #expect(openRange.location != NSNotFound)
        guard doneRange.location != NSNotFound,
              openRange.location != NSNotFound else { return }

        #expect(
            (
                rendered.attributedString.attribute(
                    .strikethroughStyle,
                    at: doneRange.location,
                    effectiveRange: nil
                ) as? NSNumber
            )?.intValue == NSUnderlineStyle.single.rawValue
        )
        #expect(
            rendered.attributedString.attribute(
                .strikethroughStyle,
                at: openRange.location,
                effectiveRange: nil
            ) == nil
        )
        #expect(
            rendered.attributedString.attribute(
                .foregroundColor,
                at: doneRange.location,
                effectiveRange: nil
            ) as? NSColor == AppKitThemeAdapter.secondary
        )

        let paragraph = rendered.attributedString.attribute(
            .paragraphStyle,
            at: doneRange.location,
            effectiveRange: nil
        ) as? NSParagraphStyle
        #expect(paragraph?.tabStops.first?.location == AtelierMetrics.spaceXL)
        #expect(paragraph?.headIndent == AtelierMetrics.spaceXL)
    }

    @Test("Native Markdown renders front matter values after its title")
    func nativeMarkdownFrontMatterCard() {
        let rendered = MarkdownAttributedDocumentBuilder.build(
            document: ParsedMarkdownDocument(
                source: """
                ---
                name: preview
                type: project
                ---

                # Title
                """
            ),
            scale: 1,
            displayScale: 2,
            usesDarkAppearance: false
        )

        #expect(
            rendered.attributedString.string
                == "Title\npreview\nproject\n"
        )
        let text = rendered.attributedString.string as NSString
        let valueRange = text.range(of: "preview")
        #expect(
            rendered.attributedString.attribute(
                .foregroundColor,
                at: valueRange.location,
                effectiveRange: nil
            ) as? NSColor == AppKitThemeAdapter.accent
        )
        #expect(rendered.headings.count == 1)
    }

    @Test("Markdown outline lists heading anchors in document order")
    func markdownOutline() {
        let markdown = """
        # Title

        Intro.

        ## Section

        ### Deep

        ## Empty heading title becomes
        """
        // trailing space-only heading should be dropped
        let withBlankHeading = markdown + "\n#   \n"
        let outline = AgentMarkdownBlock.outline(from: withBlankHeading)
        #expect(outline.map(\.title) == [
            "Title",
            "Section",
            "Deep",
            "Empty heading title becomes"
        ])
        #expect(outline.map(\.level) == [1, 2, 3, 2])
        #expect(outline.map(\.id) == [
            AgentMarkdownBlock.blockAnchorID(0),
            AgentMarkdownBlock.blockAnchorID(2),
            AgentMarkdownBlock.blockAnchorID(3),
            AgentMarkdownBlock.blockAnchorID(4)
        ])
    }

    @Test("Markdown source outline maps headings outside fenced code")
    func markdownSourceOutlineLines() {
        let source = """
        # One

        ```md
        # Hidden
        ```

        ## Two
        """
        let document = ParsedMarkdownDocument(source: source)
        let lines = MarkdownSourceOutlinePolicy.lineNumberByOutlineID(
            source: source,
            entries: document.outline
        )

        #expect(document.outline.map(\.title) == ["One", "Two"])
        #expect(lines[document.outline[0].id] == 1)
        #expect(lines[document.outline[1].id] == 7)
    }

    @Test("Markdown preview builds one continuous attributed document")
    func markdownContinuousAttributedDocument() {
        let source = """
        # Title

        Paragraph with `inline`.

        - Item

        ```swift
        let value = 1
        ```

        | Name | Value |
        | --- | --- |
        | Alpha | Beta |

        ```mermaid
        graph TD
        A --> B
        ```
        """
        let document = ParsedMarkdownDocument(source: source)
        let rendered = MarkdownAttributedDocumentBuilder.build(
            document: document,
            scale: 1,
            displayScale: 2,
            usesDarkAppearance: false
        )
        let text = rendered.attributedString.string

        #expect(rendered.headings.count == 1)
        #expect(
            (text as NSString).substring(with: rendered.headings[0].range)
                == "Title"
        )
        #expect(text.contains("Paragraph with inline."))
        #expect(text.contains("\u{2022}\tItem"))
        #expect(text.contains("let value = 1"))
        #expect(text.contains("Name"))
        #expect(text.contains("Alpha"))
        #expect(text.contains("MERMAID - SOURCE FALLBACK"))
        #expect(text.contains("graph TD"))
        #expect(rendered.codeHighlights.map(\.source) == ["let value = 1"])
    }

    @Test("Markdown fenced code adds block spacing only after its final line")
    func markdownCodeBlockLineSpacing() {
        let source = """
        ```text
        AtelierApp
        `-- ContentView
            |-- Workspace rail
        ```
        """
        let rendered = MarkdownAttributedDocumentBuilder.build(
            document: ParsedMarkdownDocument(source: source),
            scale: 1,
            displayScale: 2,
            usesDarkAppearance: false
        )
        let text = rendered.attributedString.string as NSString

        func style(for line: String) -> NSParagraphStyle? {
            let location = text.range(of: line).location
            guard location != NSNotFound else { return nil }
            return rendered.attributedString.attribute(
                .paragraphStyle,
                at: location,
                effectiveRange: nil
            ) as? NSParagraphStyle
        }

        #expect(style(for: "AtelierApp")?.paragraphSpacing == 0)
        #expect(style(for: "`-- ContentView")?.paragraphSpacing == 0)
        let rhythm = MarkdownRhythm(
            bodyFont: NSFont.systemFont(ofSize: AtelierTypography.editorSize),
            displayScale: 2
        )
        #expect(
            style(for: "    |-- Workspace rail")?.paragraphSpacing
                == rhythm.codeCard
        )
        #expect(
            rendered.codeHighlights.map(\.source)
                == ["AtelierApp\n`-- ContentView\n    |-- Workspace rail"]
        )
    }

    @Test("Markdown fenced code renders one native card with exact copy metadata")
    func markdownNativeCodeCardMetadata() {
        let source = """
        ```swift
          let value = 1
        ```
        """
        let rendered = MarkdownAttributedDocumentBuilder.build(
            document: ParsedMarkdownDocument(source: source),
            scale: 1,
            displayScale: 2,
            usesDarkAppearance: false
        )
        let text = rendered.attributedString.string as NSString
        let region = rendered.codeBlocks.first
        guard let region else {
            Issue.record("Expected one code card region")
            return
        }

        #expect(rendered.codeBlocks.count == 1)
        #expect(region.id == AgentMarkdownBlock.blockAnchorID(0))
        #expect(region.source == "  let value = 1")
        #expect(text.substring(with: region.headerRange) == "SWIFT\n")
        #expect(text.substring(with: region.sourceRange) == region.source)

        let headerStyle = rendered.attributedString.attribute(
            .paragraphStyle,
            at: region.headerRange.location,
            effectiveRange: nil
        ) as? NSParagraphStyle
        let sourceStyle = rendered.attributedString.attribute(
            .paragraphStyle,
            at: region.sourceRange.location,
            effectiveRange: nil
        ) as? NSParagraphStyle
        let headerBlock = headerStyle?.textBlocks.first as? NSTextTableBlock
        let sourceBlock = sourceStyle?.textBlocks.first as? NSTextTableBlock
        #expect(headerBlock != nil)
        #expect(sourceBlock != nil)
        #expect(headerBlock?.table === sourceBlock?.table)

        let codeFont = rendered.attributedString.attribute(
            .font,
            at: region.sourceRange.location,
            effectiveRange: nil
        ) as? NSFont
        #expect(codeFont?.familyName == AtelierTypography.codeFontFamily)
        #expect(codeFont?.pointSize == AtelierTypography.uiSize)
    }

    @Test("Markdown tables allocate bounded widths from sampled content")
    func markdownTableColumnPercentages() {
        let widths = MarkdownAttributedDocumentBuilder.tableColumnPercentages(
            headers: ["Name", "Description", "State"],
            rows: [
                ["A", "A much longer explanation that should receive more width", "On"],
                ["B", "Short", "Off"]
            ]
        )

        #expect(widths.count == 3)
        #expect(abs(widths.reduce(0, +) - 100) < 0.001)
        #expect(widths[1] > widths[0])
        #expect(widths[1] > widths[2])
        #expect(widths.allSatisfy { $0 >= 10 && $0 <= 50 })
    }

    @Test("Markdown table layout keeps every wrapped cell line")
    func markdownTableLayoutKeepsWrappedCellLines() {
        let source = """
        | State | Visual treatment | Interaction | Accessibility value |
        |---|---|---|---|
        | Active | Semibold name, brighter neutral shortcut, flat selection band | Selecting again keeps current session | `Selected, available` |
        | Inactive | Primary name, secondary shortcut, clear fill | Selects existing live session | `Available` |
        | Loading | Secondary name and shortcut, native progress indicator | Disabled until restore finishes | `Loading` |
        | Unavailable | Primary name, secondary shortcut, `questionmark.folder` accessory | Selects item and presents recovery context | `Unavailable` |
        | Error | Primary name, secondary shortcut, semantic error accessory | Selects item and presents error context | `Error` |
        | Disabled | Clear fill at disabled opacity | No action | `Disabled` |
        """
        let rendered = MarkdownAttributedDocumentBuilder.build(
            document: ParsedMarkdownDocument(source: source),
            scale: 1,
            displayScale: 2,
            usesDarkAppearance: false
        )

        let storage = NSTextStorage(attributedString: rendered.attributedString)
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(
            containerSize: NSSize(
                width: 720,
                height: CGFloat.greatestFiniteMagnitude
            )
        )
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)
        layoutManager.ensureLayout(for: textContainer)

        var cellBounds: [NSRect] = []
        var maximumLineCount = 0
        rendered.attributedString.enumerateAttribute(
            .paragraphStyle,
            in: NSRange(location: 0, length: rendered.attributedString.length)
        ) { value, range, _ in
            guard let style = value as? NSParagraphStyle,
                  let block = style.textBlocks.first as? NSTextTableBlock else { return }
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: range,
                actualCharacterRange: nil
            )
            var lineCount = 0
            layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, _, _, _, _ in
                lineCount += 1
            }
            maximumLineCount = max(maximumLineCount, lineCount)

            let contentRect = layoutManager.boundingRect(
                forGlyphRange: glyphRange,
                in: textContainer
            )
            let blockRect = layoutManager.boundsRect(
                for: block,
                glyphRange: glyphRange
            )
            #expect(blockRect.minY <= contentRect.minY)
            #expect(blockRect.maxY >= contentRect.maxY)
            cellBounds.append(blockRect)
        }

        #expect(cellBounds.count == 28)
        #expect(maximumLineCount >= 4)
        for rowStart in stride(from: 0, to: cellBounds.count, by: 4) {
            let rowBounds = cellBounds[rowStart..<(rowStart + 4)]
            guard let first = rowBounds.first else { continue }
            #expect(rowBounds.allSatisfy { $0.minY == first.minY })
            #expect(rowBounds.allSatisfy { $0.maxY == first.maxY })
        }
    }

    @Test("Markdown outline selection follows document scroll offsets")
    func markdownOutlineScrollSync() {
        let entries = [
            MarkdownOutlineEntry(id: "h1", level: 1, title: "One"),
            MarkdownOutlineEntry(id: "h2", level: 2, title: "Two"),
            MarkdownOutlineEntry(id: "h3", level: 2, title: "Three")
        ]
        let offsets: [String: CGFloat] = [
            "h1": 0,
            "h2": 400,
            "h3": 900
        ]
        #expect(
            MarkdownOutlineSyncPolicy.activeOutlineID(
                entries: entries,
                offsets: offsets,
                contentOffsetY: 0
            ) == "h1"
        )
        #expect(
            MarkdownOutlineSyncPolicy.activeOutlineID(
                entries: entries,
                offsets: offsets,
                contentOffsetY: 380
            ) == "h2"
        )
        #expect(
            MarkdownOutlineSyncPolicy.activeOutlineID(
                entries: entries,
                offsets: offsets,
                contentOffsetY: 1_000
            ) == "h3"
        )
        #expect(
            MarkdownOutlineSyncPolicy.activeOutlineID(
                entries: entries,
                offsets: [:],
                contentOffsetY: 200
            ) == "h1"
        )

        let store = MarkdownHeadingOffsetStore()
        store.setOffset(id: "h1", y: 0.2)
        store.setOffset(id: "h2", y: 400.1)
        store.setOffset(id: "h3", y: 900.4)
        store.setContentOffset(380)
        #expect(store.activeOutlineID(entries: entries) == "h2")
        store.setSuppressSyncUntil(Date().addingTimeInterval(1))
        #expect(store.isSyncSuppressed)
        store.setSuppressSyncUntil(nil)
        #expect(!store.isSyncSuppressed)
        #expect(
            MarkdownOutlineSyncPolicy.quantizeOffset(10.1)
                == MarkdownOutlineSyncPolicy.quantizeOffset(10.2)
        )
        #expect(
            MarkdownOutlineSyncPolicy.quantizeOffset(10.1)
                != MarkdownOutlineSyncPolicy.quantizeOffset(10.6)
        )
        #expect(
            MarkdownOutlineSyncPolicy.nearestMeasuredID(
                targetID: "h3",
                entries: entries,
                offsets: ["h1": 0, "h2": 400]
            ) == "h2"
        )
        #expect(
            MarkdownOutlineSyncPolicy.nearestMeasuredID(
                targetID: "h1",
                entries: entries,
                offsets: ["h1": 0]
            ) == "h1"
        )
        #expect(
            MarkdownOutlineSyncPolicy.clampedContentOffset(
                targetY: 9_999,
                viewportHeight: 800,
                contentHeight: 2_000
            ) == 1_200
        )

        let document = ParsedMarkdownDocument(source: "# Title\n\nHello `x`\n")
        #expect(document.blocks.count == 2)
        #expect(document.inlineRuns.count == 2)
        #expect(document.inlineRuns[0] != nil)
        #expect(document.inlineRuns[1] != nil)
        #expect(AgentMarkdownBlock.inlineSource(for: document.blocks[0]) == "Title")
    }

    @Test("Bounded code display keeps complete copy source")
    func codeCopyPolicy() {
        let source = String(repeating: "x", count: AgentCodeBlockPolicy.displayLimit + 25)
        #expect(AgentCodeBlockPolicy.displayedContent(source).hasSuffix("\n..."))
        #expect(AgentCodeBlockPolicy.displayedContent(source).count < source.count)
        #expect(AgentCodeBlockPolicy.copiedContent(source) == source)
    }

    @Test("Markdown code languages map common fence aliases")
    func codeHighlightLanguageAliases() {
        #expect(AgentCodeHighlightPolicy.languageName(for: "js") == "javaScript")
        #expect(AgentCodeHighlightPolicy.languageName(for: "tsx") == "typeScript")
        #expect(AgentCodeHighlightPolicy.languageName(for: "c++") == "cPlusPlus")
        #expect(AgentCodeHighlightPolicy.languageName(for: "swift") == "swift")
        #expect(AgentCodeHighlightPolicy.languageName(for: "  ") == nil)
        #expect(AgentCodeHighlightPolicy.languageName(for: nil) == nil)
    }

    @Test("Markdown code highlighting preserves source and adds token colors")
    func codeHighlightingPreservesSource() async throws {
        let source = "  let claim = true\n"
        let attributed = try await SyntaxHighlightService().highlightPreservingWhitespace(
            source,
            languageName: "swift",
            usesDarkAppearance: false
        )
        let native = NSAttributedString(attributed)
        var coloredRangeCount = 0
        native.enumerateAttribute(
            .foregroundColor,
            in: NSRange(location: 0, length: native.length)
        ) { value, _, _ in
            if value != nil { coloredRangeCount += 1 }
        }

        #expect(String(attributed.characters) == source)
        #expect(coloredRangeCount > 1)
    }

    @Test("Markdown inline code receives accent block styling")
    func inlineCodeStyling() {
        let attributed = AgentMarkdownInlinePolicy.attributedString("Run `claim()` now")
        let codeRun = attributed.runs.first { run in
            run.inlinePresentationIntent?.contains(.code) == true
        }

        #expect(codeRun?.foregroundColor != nil)
        #expect(codeRun?.backgroundColor != nil)
    }

    @Test("Native Markdown inline code draws one fill with outside margin")
    func nativeMarkdownInlineCodePadding() {
        let rendered = MarkdownAttributedDocumentBuilder.build(
            document: ParsedMarkdownDocument(
                source: "A`dpq`B"
            ),
            scale: 1,
            displayScale: 2,
            usesDarkAppearance: false
        )
        let renderedText = rendered.attributedString.string as NSString
        let codeRange = renderedText.range(of: "dpq")
        #expect(codeRange.location != NSNotFound)
        guard codeRange.location != NSNotFound else { return }

        #expect(rendered.attributedString.string == "AdpqB\n")
        #expect(
            rendered.attributedString.attribute(
                .backgroundColor,
                at: codeRange.location,
                effectiveRange: nil
            ) == nil
        )
        #expect(
            rendered.attributedString.attribute(
                .atelierInlineCode,
                at: codeRange.location,
                effectiveRange: nil
            ) != nil
        )

        let mutable = NSMutableAttributedString(
            attributedString: rendered.attributedString
        )
        mutable.addAttribute(
            .atelierInlineCode,
            value: NSColor(
                srgbRed: 1,
                green: 0,
                blue: 0,
                alpha: 1
            ),
            range: codeRange
        )
        mutable.addAttribute(
            .foregroundColor,
            value: NSColor.black,
            range: codeRange
        )
        mutable.addAttribute(
            .foregroundColor,
            value: NSColor.blue,
            range: NSRange(location: 0, length: 1)
        )
        mutable.addAttribute(
            .foregroundColor,
            value: NSColor.blue,
            range: NSRange(location: NSMaxRange(codeRange), length: 1)
        )
        let storage = NSTextStorage(attributedString: mutable)
        let layoutManager = MarkdownPreviewLayoutManager(
            metrics: MarkdownPreviewDecorationMetrics(
                inlineCodePadding: NSSize(width: 8, height: 4),
                inlineCodeHorizontalReservation: 12,
                headingRuleThickness: 1.5,
                headingRulePrimaryLead: 32,
                headingRuleSecondaryLead: 16,
                hairline: 0.5,
                quoteGlyphFontSize: 38,
                quoteGlyphAlpha: 0.18,
                codeLineNumberGap: 8
            )
        )
        storage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(
            containerSize: NSSize(width: 160, height: 60)
        )
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)
        layoutManager.ensureLayout(for: textContainer)

        let codeGlyphRange = layoutManager.glyphRange(
            forCharacterRange: codeRange,
            actualCharacterRange: nil
        )
        let fullGlyphRange = layoutManager.glyphRange(for: textContainer)
        let codeLayoutBounds = layoutManager.boundingRect(
            forGlyphRange: codeGlyphRange,
            in: textContainer
        )
        #expect(
            (storage.attribute(.kern, at: 0, effectiveRange: nil) as? NSNumber)?
                .doubleValue == 12
        )
        #expect(
            (
                storage.attribute(
                    .kern,
                    at: NSMaxRange(codeRange) - 1,
                    effectiveRange: nil
                ) as? NSNumber
            )?.doubleValue == 12
        )

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 200,
            pixelsHigh: 100,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
            Issue.record("Expected a bitmap context for inline-code rendering")
            return
        }
        let drawOrigin = NSPoint(x: 24, y: 24)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: 200, height: 100).fill()
        // TextKit lays out in a flipped space like NSTextView. Flip the CTM and
        // hand TextKit a context that reports `flipped`, so glyphs and
        // decorations land in the same vertical space as the app.
        graphics.cgContext.translateBy(x: 0, y: 100)
        graphics.cgContext.scaleBy(x: 1, y: -1)
        let flippedContext = NSGraphicsContext(
            cgContext: graphics.cgContext,
            flipped: true
        )
        NSGraphicsContext.current = flippedContext
        layoutManager.drawBackground(
            forGlyphRange: fullGlyphRange,
            at: drawOrigin
        )
        layoutManager.drawGlyphs(
            forGlyphRange: fullGlyphRange,
            at: drawOrigin
        )
        flippedContext.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        var redBounds = NSRect.null
        var codeInk = NSRect.null
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?
                    .usingColorSpace(.sRGB) else {
                    continue
                }
                if color.redComponent > 0.8,
                   color.greenComponent < 0.2,
                   color.blueComponent < 0.2,
                   color.alphaComponent > 0.8 {
                    redBounds = redBounds.union(
                        NSRect(x: x, y: y, width: 1, height: 1)
                    )
                } else if color.redComponent < 0.25,
                          color.greenComponent < 0.25,
                          color.blueComponent < 0.25,
                          color.alphaComponent > 0.8 {
                    codeInk = codeInk.union(
                        NSRect(x: x, y: y, width: 1, height: 1)
                    )
                }
            }
        }
        guard !redBounds.isNull, !codeInk.isNull else {
            Issue.record("Expected a rendered inline-code background and ink")
            return
        }
        var leftTextMaxX: CGFloat?
        var rightTextMinX: CGFloat?
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?
                    .usingColorSpace(.sRGB) else {
                    continue
                }
                if color.blueComponent > 0.7,
                   color.redComponent < 0.3,
                   color.greenComponent < 0.5,
                   color.alphaComponent > 0.5 {
                    let pixelX = CGFloat(x)
                    if pixelX < redBounds.minX {
                        leftTextMaxX = max(leftTextMaxX ?? pixelX, pixelX)
                    } else if pixelX > redBounds.maxX {
                        rightTextMinX = min(rightTextMinX ?? pixelX, pixelX)
                    }
                }
            }
        }
        // Inner padding must read as equal on both sides regardless of how the
        // code font reports the last glyph's kerned advance.
        let leftPad = codeInk.minX - redBounds.minX
        let rightPad = redBounds.maxX - codeInk.maxX
        #expect(abs(leftPad - rightPad) <= 2)
        #expect(leftPad >= 4)
        #expect(rightPad >= 4)
        // Vertical padding must read the same above and below the text. The line
        // fragment carries the paragraph's lineSpacing below the glyphs, so a
        // fragment-derived fill would sit high with a fat bottom gap.
        let topPad = codeInk.minY - redBounds.minY
        let bottomPad = redBounds.maxY - codeInk.maxY
        #expect(topPad >= 3)
        #expect(bottomPad >= 3)
        // Slack differs only by the font box: ascender sits above cap height.
        #expect(abs(topPad - bottomPad) <= 3)
        #expect(redBounds.height < codeLayoutBounds.height + 2 * 4)
        #expect(leftTextMaxX != nil)
        #expect(rightTextMinX != nil)
        if let leftTextMaxX, let rightTextMinX {
            #expect(redBounds.minX - leftTextMaxX >= 3)
            #expect(rightTextMinX - redBounds.maxX >= 3)
        }
    }

    @Test("Markdown file previews decorate CSS hex colors with matching swatches")
    func markdownColorTokenSwatches() {
        let source = "Colors #abc #abcd #E7E3DD #11223380, not #12345, #E7E3DD0, or #abcxyz"
        let plain = AgentMarkdownInlinePolicy.attributedString(source)
        let decorated = AgentMarkdownInlinePolicy.attributedString(
            source,
            showsColorSwatches: true
        )
        let pureCode = AgentMarkdownInlinePolicy.plainAttributedString(
            "#E7E3DD",
            showsColorSwatches: true
        )

        #expect(String(plain.characters) == source)
        #expect(
            String(decorated.characters)
                == "Colors \u{25A0}#abc \u{25A0}#abcd \u{25A0}#E7E3DD "
                    + "\u{25A0}#11223380, not #12345, #E7E3DD0, or #abcxyz"
        )
        #expect(String(pureCode.characters) == "\u{25A0}#E7E3DD")

        let swatchRun = pureCode.runs.first { run in
            String(pureCode.characters[run.range]) == "\u{25A0}"
        }
        guard let color = swatchRun?.foregroundColor else {
            Issue.record("Expected an sRGB color on the preview swatch")
            return
        }
        #expect(swatchRun?.font == .system(size: AtelierTypography.editorSize))
        let resolved = color.resolve(in: EnvironmentValues())
        #expect(abs(resolved.red - (231.0 / 255.0)) < 0.001)
        #expect(abs(resolved.green - (227.0 / 255.0)) < 0.001)
        #expect(abs(resolved.blue - (221.0 / 255.0)) < 0.001)
        #expect(abs(resolved.opacity - 1.0) < 0.001)
    }

    @Test("Native Markdown preview preserves hex swatch colors inside inline code")
    func nativeMarkdownInlineCodeSwatchColor() {
        let rendered = MarkdownAttributedDocumentBuilder.build(
            document: ParsedMarkdownDocument(source: "`#E7E3DD`"),
            scale: 1,
            displayScale: 2,
            usesDarkAppearance: false
        )
        let text = rendered.attributedString.string as NSString
        let swatchRange = text.range(of: "\u{25A0}")
        guard swatchRange.location != NSNotFound,
              let color = rendered.attributedString.attribute(
                .foregroundColor,
                at: swatchRange.location,
                effectiveRange: nil
              ) as? NSColor,
              let resolved = color.usingColorSpace(.sRGB) else {
            Issue.record("Expected an sRGB color on the native preview swatch")
            return
        }

        #expect(text.range(of: "\u{25A0}#E7E3DD").location != NSNotFound)
        #expect(abs(resolved.redComponent - (231.0 / 255.0)) < 0.001)
        #expect(abs(resolved.greenComponent - (227.0 / 255.0)) < 0.001)
        #expect(abs(resolved.blueComponent - (221.0 / 255.0)) < 0.001)
        #expect(abs(resolved.alphaComponent - 1.0) < 0.001)
    }

    @Test("Pure inline code cells extract continuous chip content")
    func pureInlineCodeContent() {
        #expect(
            AgentMarkdownInlinePolicy.pureCodeContent(
                "`.claude/skills/gitnexus/gitnexus-exploring/SKILL.md`"
            ) == ".claude/skills/gitnexus/gitnexus-exploring/SKILL.md"
        )
        #expect(AgentMarkdownInlinePolicy.pureCodeContent("plain path") == nil)
        #expect(AgentMarkdownInlinePolicy.pureCodeContent("see `mixed` text") == nil)
        #expect(AgentMarkdownInlinePolicy.pureCodeContent("``") == nil)
        #expect(AgentMarkdownInlinePolicy.pureCodeContent("`a` and `b`") == nil)
    }

    @Test("Markdown GitHub callouts parse and build as native cards")
    func markdownCallout() {
        let source = MarkdownCalloutKind.allCases.map {
            "> [!\($0.rawValue)]\n> Body for \($0.rawValue)"
        }.joined(separator: "\n\n")
        let blocks = AgentMarkdownBlock.parse(source)

        #expect(blocks.count == MarkdownCalloutKind.allCases.count)
        for (index, kind) in MarkdownCalloutKind.allCases.enumerated() {
            #expect(
                blocks[index] == .callout(
                    kind: kind,
                    content: "Body for \(kind.rawValue)"
                )
            )
        }
        #expect(AgentMarkdownBlock.parse("> Ordinary") == [.quote("Ordinary")])

        let rendered = MarkdownAttributedDocumentBuilder.build(
            document: ParsedMarkdownDocument(source: source),
            scale: 1,
            displayScale: 2,
            usesDarkAppearance: false
        )
        #expect(!rendered.attributedString.string.contains("[!"))
        for kind in MarkdownCalloutKind.allCases {
            let text = rendered.attributedString.string as NSString
            let label = text.range(of: kind.rawValue)
            let body = text.range(of: "Body for \(kind.rawValue)")
            #expect(label.location != NSNotFound)
            #expect(body.location != NSNotFound)
            if body.location != NSNotFound {
                let paragraph = rendered.attributedString.attribute(
                    .paragraphStyle,
                    at: body.location,
                    effectiveRange: nil
                ) as? NSParagraphStyle
                #expect(paragraph?.textBlocks.first is NSTextTableBlock)
                #expect(
                    rendered.attributedString.attribute(
                        .foregroundColor,
                        at: body.location,
                        effectiveRange: nil
                    ) as? NSColor == AppKitThemeAdapter.foreground
                )
            }
        }
    }

    @Test("Markdown lists preserve depth, continuation, and capped gutters")
    func markdownNestedList() {
        let source = """
        - Root
          - Child
            - Grandchild
                  - Capped
          continuation for capped
        1. Ordered
            2. Ordered nested
        - [ ] Task
              - [x] Task nested
        """
        let blocks = AgentMarkdownBlock.parse(source)
        #expect(blocks == [
            .unorderedItem(depth: 0, content: "Root"),
            .unorderedItem(depth: 1, content: "Child"),
            .unorderedItem(depth: 2, content: "Grandchild"),
            .unorderedItem(depth: 3, content: "Capped continuation for capped"),
            .orderedItem(number: 1, depth: 0, content: "Ordered"),
            .orderedItem(number: 2, depth: 2, content: "Ordered nested"),
            .taskItem(isCompleted: false, depth: 0, content: "Task"),
            .taskItem(isCompleted: true, depth: 3, content: "Task nested")
        ])

        let rendered = MarkdownAttributedDocumentBuilder.build(
            document: ParsedMarkdownDocument(source: source),
            scale: 1,
            displayScale: 2,
            usesDarkAppearance: false
        )
        let text = rendered.attributedString.string as NSString
        for (value, depth) in [
            ("Root", 0),
            ("Child", 1),
            ("Grandchild", 2),
            ("Capped", 3)
        ] {
            let range = text.range(of: value)
            let paragraph = rendered.attributedString.attribute(
                .paragraphStyle,
                at: range.location,
                effectiveRange: nil
            ) as? NSParagraphStyle
            let expected = AtelierMetrics.spaceXL
                + CGFloat(depth) * AtelierMetrics.spaceXL
            #expect(paragraph?.headIndent == expected)
            #expect(paragraph?.tabStops.first?.location == expected)
        }
    }

    @Test("Transcript ordered and task markers fade with nested depth")
    @MainActor
    func markdownTranscriptListMarkerDepth() {
        func markerStrength(source: String, xOffset: CGFloat) -> Double {
            let renderer = ImageRenderer(
                content: AgentMarkdownView(source: source)
                    .frame(width: 220, height: 52, alignment: .topLeading)
                    .background(Color.white)
                    .environment(\.colorScheme, .light)
            )
            renderer.scale = 2
            guard let image = renderer.cgImage else {
                Issue.record("Expected transcript marker image")
                return 0
            }
            let bitmap = NSBitmapImageRep(cgImage: image)
            let xStart = max(0, Int((xOffset * renderer.scale).rounded(.down)))
            let xEnd = min(
                bitmap.pixelsWide,
                Int(((xOffset + 18) * renderer.scale).rounded(.up))
            )
            var maximum = 0.0
            for y in 0..<bitmap.pixelsHigh {
                for x in xStart..<xEnd {
                    guard let color = bitmap.colorAt(x: x, y: y)?
                        .usingColorSpace(.sRGB) else {
                        continue
                    }
                    let strength = (1 - color.redComponent)
                        + (1 - color.greenComponent)
                        + (1 - color.blueComponent)
                    maximum = max(maximum, strength)
                }
            }
            return maximum
        }

        let nestedOffset = AtelierMetrics.spaceXL * 3
        let orderedRoot = markerStrength(source: "1. Root", xOffset: 0)
        let orderedNested = markerStrength(
            source: "      1. Nested",
            xOffset: nestedOffset
        )
        let taskRoot = markerStrength(source: "- [ ] Root", xOffset: 0)
        let taskNested = markerStrength(
            source: "      - [ ] Nested",
            xOffset: nestedOffset
        )

        #expect(orderedRoot > 0)
        #expect(orderedNested < orderedRoot * 0.75)
        #expect(taskRoot > 0)
        #expect(taskNested < taskRoot * 0.75)
    }

    @Test("Markdown tables honor delimiter and numeric-majority alignment")
    func markdownTableAlignment() {
        let source = """
        | Item | State | Count |
        | :-- | :-: | --: |
        | Alpha | Ready | 10 |
        | Beta | Waiting | 2 |
        | Gamma | Ready | none |
        """
        let blocks = AgentMarkdownBlock.parse(source)
        #expect(blocks == [
            .table(
                headers: ["Item", "State", "Count"],
                alignments: [.left, .center, .right],
                rows: [
                    ["Alpha", "Ready", "10"],
                    ["Beta", "Waiting", "2"],
                    ["Gamma", "Ready", "none"]
                ]
            )
        ])

        let rendered = MarkdownAttributedDocumentBuilder.build(
            document: ParsedMarkdownDocument(source: source),
            scale: 1,
            displayScale: 2,
            usesDarkAppearance: false
        )
        let text = rendered.attributedString.string as NSString
        for (value, expected) in [
            ("Alpha", NSTextAlignment.left),
            ("Ready", NSTextAlignment.center),
            ("10", NSTextAlignment.right)
        ] {
            let range = text.range(of: value)
            let paragraph = rendered.attributedString.attribute(
                .paragraphStyle,
                at: range.location,
                effectiveRange: nil
            ) as? NSParagraphStyle
            #expect(paragraph?.alignment == expected)
        }
        #expect(
            MarkdownTableAlignmentPolicy.numericMajorityColumns(
                headers: ["Item", "Count"],
                rows: [["A", "1"], ["B", "2"], ["C", "none"]]
            ) == [1]
        )
    }

    @Test("Native Markdown uses one snapped font-derived rhythm")
    func nativeMarkdownRhythm() {
        let bodyFont = NSFont.systemFont(ofSize: AtelierTypography.editorSize)
        let rhythm = MarkdownRhythm(bodyFont: bodyFont, displayScale: 2)
        let source = """
        # Title

        Opening.

        ### Detail

        Body.

        ---

        ```text
        code
        ```
        """
        let rendered = MarkdownAttributedDocumentBuilder.build(
            document: ParsedMarkdownDocument(source: source),
            scale: 1,
            displayScale: 2,
            usesDarkAppearance: false
        )
        let text = rendered.attributedString.string as NSString
        func style(_ value: String) -> NSParagraphStyle? {
            let range = text.range(of: value)
            guard range.location != NSNotFound else { return nil }
            return rendered.attributedString.attribute(
                .paragraphStyle,
                at: range.location,
                effectiveRange: nil
            ) as? NSParagraphStyle
        }

        #expect(rhythm.unit * 2 == (rhythm.unit * 2).rounded(.toNearestOrAwayFromZero))
        #expect(style("Opening.")?.paragraphSpacing == rhythm.lede)
        #expect(style("Detail")?.paragraphSpacingBefore == rhythm.heading3Before)
        #expect(style("Detail")?.paragraphSpacing == rhythm.heading3After)
        #expect(style("Body.")?.paragraphSpacing == rhythm.paragraph)
        #expect(style("TEXT")?.paragraphSpacingBefore == rhythm.codeCard)
        #expect(style("code")?.paragraphSpacing == rhythm.codeCard)
    }

    @Test("Markdown local image figures keep stable bounds and skip remote URLs")
    func markdownImageFigure() async {
        let directory = temporaryDirectory("markdown-image")
        let localURL = directory.appendingPathComponent("figure.png")
        let png = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        )
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try? png?.write(to: localURL)

        #expect(
            AgentMarkdownBlock.parse("![Exact caption](figure.png)") == [
                .image(altText: "Exact caption", urlText: "figure.png")
            ]
        )
        #expect(
            MarkdownImageFigurePolicy.localURL(
                urlText: "https://example.com/image.png",
                directoryURL: directory
            ) == nil
        )

        let rendered = MarkdownAttributedDocumentBuilder.build(
            document: ParsedMarkdownDocument(
                source: "![Exact caption](figure.png)",
                sourceDirectoryURL: directory
            ),
            scale: 1,
            displayScale: 2,
            usesDarkAppearance: false
        )
        #expect(rendered.imageFigures.count == 1)
        guard let region = rendered.imageFigures.first else { return }
        #expect(region.url == localURL.standardizedFileURL)
        #expect(region.attachment.bounds == region.bounds)
        #expect(rendered.attributedString.string.contains("Exact caption"))
        let decoded = await MarkdownLocalImageLoader.load(region.url)
        #expect(decoded?.width == 1)
        #expect(decoded?.height == 1)
        #expect(decoded?.pixels.count == 4)
        #expect(decoded?.cgImage() != nil)
        #expect(region.attachment.bounds == region.bounds)

        let cancelledLoad = Task {
            await MarkdownLocalImageLoader.load(region.url)
        }
        cancelledLoad.cancel()
        #expect(await cancelledLoad.value == nil)

        let remote = MarkdownAttributedDocumentBuilder.build(
            document: ParsedMarkdownDocument(
                source: "![Remote](https://example.com/image.png)",
                sourceDirectoryURL: directory
            ),
            scale: 1,
            displayScale: 2,
            usesDarkAppearance: false
        )
        #expect(remote.imageFigures.isEmpty)
    }

    @Test("Native Markdown code numbers stay inside the gutter and preserve source")
    func markdownCodeLineNumbers() {
        let source = "first\n  second\nthird"
        let rendered = MarkdownAttributedDocumentBuilder.build(
            document: ParsedMarkdownDocument(
                source: "```swift\n\(source)\n```"
            ),
            scale: 1,
            displayScale: 2,
            usesDarkAppearance: false
        )
        guard let region = rendered.codeBlocks.first else {
            Issue.record("Expected one numbered code region")
            return
        }
        let text = rendered.attributedString.string as NSString
        #expect(region.usesGeneratedLineNumbers)
        #expect(region.source == source)
        #expect(text.substring(with: region.sourceRange) == source)
        #expect(rendered.codeHighlights.first?.range == region.sourceRange)
        let paragraph = rendered.attributedString.attribute(
            .paragraphStyle,
            at: region.sourceRange.location,
            effectiveRange: nil
        ) as? NSParagraphStyle
        var lineNumberCount = 0
        rendered.attributedString.enumerateAttribute(
            .atelierCodeLineNumber,
            in: region.sourceRange
        ) { value, _, _ in
            if value != nil {
                lineNumberCount += 1
            }
        }
        #expect(lineNumberCount == 3)
        #expect(paragraph?.textLists.isEmpty == true)
        #expect(paragraph?.tabStops.count == 2)

        let measure: CGFloat = 320
        let storage = NSTextStorage(attributedString: rendered.attributedString)
        let layoutManager = MarkdownPreviewLayoutManager(metrics: .current)
        storage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(
            containerSize: NSSize(width: measure, height: 200)
        )
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)
        layoutManager.ensureLayout(for: textContainer)

        let firstLineGlyphRange = layoutManager.glyphRange(
            forCharacterRange: NSRange(
                location: region.sourceRange.location,
                length: 1
            ),
            actualCharacterRange: nil
        )
        var fragment = NSRect.zero
        var usedFragment = NSRect.zero
        layoutManager.enumerateLineFragments(
            forGlyphRange: firstLineGlyphRange
        ) { lineRect, usedRect, _, _, stop in
            fragment = lineRect
            usedFragment = usedRect
            stop.pointee = true
        }
        #expect(usedFragment.minX > fragment.minX)
        let baseline = fragment.minY
            + layoutManager.location(forGlyphAt: firstLineGlyphRange.location).y

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(measure),
            pixelsHigh: 200,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let bitmapGraphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
            Issue.record("Expected a bitmap context for code-number rendering")
            return
        }
        let bitmapContext = bitmapGraphics.cgContext
        bitmapContext.translateBy(x: 0, y: CGFloat(bitmap.pixelsHigh))
        bitmapContext.scaleBy(x: 1, y: -1)
        let graphics = NSGraphicsContext(
            cgContext: bitmapContext,
            flipped: true
        )
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: measure, height: 200).fill()
        NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
            layoutManager.drawBackground(
                forGlyphRange: layoutManager.glyphRange(for: textContainer),
                at: .zero
            )
        }
        graphics.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        let backgroundX = Int(fragment.minX.rounded(.up)) + 2
        let gutterStartX = backgroundX + 2
        let gutterEndX = Int(usedFragment.minX.rounded(.down)) - 2
        let rowStart = max(0, Int(fragment.minY.rounded(.down)))
        let rowEnd = min(
            bitmap.pixelsHigh - 1,
            Int(fragment.maxY.rounded(.up))
        )
        var numberInkX: [Int] = []
        var numberInkY: [Int] = []
        if gutterStartX <= gutterEndX, rowStart <= rowEnd {
            for y in rowStart...rowEnd {
                guard let background = bitmap.colorAt(
                    x: backgroundX,
                    y: y
                )?.usingColorSpace(.deviceRGB) else {
                    continue
                }
                for x in gutterStartX...gutterEndX {
                    guard let color = bitmap.colorAt(
                        x: x,
                        y: y
                    )?.usingColorSpace(.deviceRGB) else {
                        continue
                    }
                    let difference = abs(color.redComponent - background.redComponent)
                        + abs(color.greenComponent - background.greenComponent)
                        + abs(color.blueComponent - background.blueComponent)
                    if difference > 0.05 {
                        numberInkX.append(x)
                        numberInkY.append(y)
                    }
                }
            }
        }
        #expect(!numberInkX.isEmpty)
        #expect(CGFloat(numberInkX.min() ?? -1) >= fragment.minX)
        #expect(CGFloat(numberInkX.max() ?? Int.max) < usedFragment.minX)
        #expect(CGFloat(numberInkY.max() ?? Int.max) <= ceil(baseline) + 1)
    }

    @Test("Native Markdown caches quote glyph geometry and optically outdents markers")
    func nativeMarkdownOpticalMarkers() {
        let rendered = MarkdownAttributedDocumentBuilder.build(
            document: ParsedMarkdownDocument(source: "> Quote\n\n- Item"),
            scale: 1,
            displayScale: 2,
            usesDarkAppearance: false
        )
        let text = rendered.attributedString.string as NSString
        let quoteRange = text.range(of: "Quote")
        let itemRange = text.range(of: "Item")
        #expect(
            rendered.attributedString.attribute(
                .atelierBlockquoteBar,
                at: quoteRange.location,
                effectiveRange: nil
            ) != nil
        )
        let itemStyle = rendered.attributedString.attribute(
            .paragraphStyle,
            at: itemRange.location,
            effectiveRange: nil
        ) as? NSParagraphStyle
        #expect(itemStyle?.firstLineHeadIndent == -1)
        #expect(itemStyle?.headIndent == AtelierMetrics.spaceXL)

        let storage = NSTextStorage(attributedString: rendered.attributedString)
        let layoutManager = MarkdownPreviewLayoutManager(metrics: .current)
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(
            containerSize: NSSize(width: 240, height: 160)
        )
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        layoutManager.ensureLayout(for: container)
        let glyphRange = layoutManager.glyphRange(for: container)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 240,
            pixelsHigh: 160,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
            Issue.record("Expected quote bitmap")
            return
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        layoutManager.drawBackground(forGlyphRange: glyphRange, at: .zero)
        graphics.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        var glyphPixelCount = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 10..<bitmap.pixelsWide {
                if let color = bitmap.colorAt(x: x, y: y),
                   color.alphaComponent > 0.05 {
                    glyphPixelCount += 1
                }
            }
        }
        #expect(glyphPixelCount > 0)
    }

    @Test("Native Markdown front matter yields title masthead lede then card")
    func nativeMarkdownFrontMatterMasthead() {
        let source = """
        ---
        title: Metadata title
        author: Hiep
        date: 2026-07-26
        kind: guide
        summary: This value is deliberately much longer than the masthead limit for fallback.
        ---
        # Visible Title

        Opening lede.
        """
        let document = ParsedMarkdownDocument(source: source)
        let plan = MarkdownFrontMatterMastheadPolicy.plan(blocks: document.blocks)
        #expect(plan?.masthead.map(\.key) == ["author", "date", "kind"])
        #expect(plan?.remaining.map(\.key) == ["title", "summary"])
        #expect(MarkdownDocumentTypePolicy.hasLedeParagraph(blocks: document.blocks))

        let rendered = MarkdownAttributedDocumentBuilder.build(
            document: document,
            scale: 1,
            displayScale: 2,
            usesDarkAppearance: false
        )
        let text = rendered.attributedString.string
        let title = text.range(of: "Visible Title")
        let author = text.range(of: "Hiep")
        let lede = text.range(of: "Opening lede.")
        let metadata = text.range(of: "Metadata title")
        #expect(title != nil && author != nil && lede != nil && metadata != nil)
        if let title, let author, let lede, let metadata {
            #expect(title.lowerBound < author.lowerBound)
            #expect(author.lowerBound < lede.lowerBound)
            #expect(lede.lowerBound < metadata.lowerBound)
        }
    }

    @Test("Markdown footnotes number resolved references and preserve unresolved syntax")
    func markdownFootnotes() {
        let source = """
        # Title

        Alpha[^a], beta[^missing], then alpha again[^a] and gamma[^b].

        | Item | Note |
        | :-- | --: |
        | Table | Table reference[^table] |

        [^b]: Second note.
        [^a]: First note.
        [^table]: Table note.
        """
        let document = ParsedMarkdownDocument(source: source)
        guard case .footnotes(let notes) = document.blocks.last else {
            Issue.record("Expected trailing footnotes block")
            return
        }
        #expect(notes == [
            MarkdownFootnote(id: "a", number: 1, text: "First note."),
            MarkdownFootnote(id: "b", number: 2, text: "Second note."),
            MarkdownFootnote(id: "table", number: 3, text: "Table note.")
        ])
        #expect(document.outline.map(\.title) == ["Title"])
        let inlineRuns = document.inlineRuns.compactMap { $0 }
        #expect(
            inlineRuns.contains {
                String($0.characters).contains("Alpha1")
                    && !String($0.characters).contains("[^a]")
            }
        )
        let transcriptInline = AgentMarkdownInlinePolicy.attributedString(
            "Transcript[^a]",
            footnoteNumbers: MarkdownFootnotePolicy.numberMap(in: document.blocks)
        )
        #expect(String(transcriptInline.characters) == "Transcript1")

        let rendered = MarkdownAttributedDocumentBuilder.build(
            document: document,
            scale: 1,
            displayScale: 2,
            usesDarkAppearance: false
        )
        let text = rendered.attributedString.string as NSString
        #expect(!rendered.attributedString.string.contains("[^a]"))
        #expect(rendered.attributedString.string.contains("[^missing]"))
        #expect(rendered.attributedString.string.contains("NOTES"))
        #expect(rendered.attributedString.string.contains("Table reference3"))
        #expect(rendered.headings.count == 1)
        let alpha = text.range(of: "Alpha")
        let reference = NSRange(
            location: NSMaxRange(alpha),
            length: 1
        )
        #expect(text.substring(with: reference) == "1")
        #expect(
            (
                rendered.attributedString.attribute(
                    .baselineOffset,
                    at: reference.location,
                    effectiveRange: nil
                ) as? NSNumber
            )?.doubleValue == 4
        )
    }

    @Test("Markdown links stay quiet and reading progress is pixel-quantized")
    func markdownLinkAndProgress() {
        let rendered = MarkdownAttributedDocumentBuilder.build(
            document: ParsedMarkdownDocument(
                source: "[Atelier](https://example.com)"
            ),
            scale: 1,
            displayScale: 2,
            usesDarkAppearance: false
        )
        let range = (rendered.attributedString.string as NSString).range(of: "Atelier")
        #expect(
            rendered.attributedString.attribute(
                .link,
                at: range.location,
                effectiveRange: nil
            ) != nil
        )

        let storage = NSTextStorage(
            attributedString: NSAttributedString(
                string: "Atelier",
                attributes: [.link: URL(string: "https://example.com") as Any]
            )
        )
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(
            containerSize: NSSize(width: 240, height: 60)
        )
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)
        let textView = MarkdownPreviewTextView(
            frame: NSRect(x: 0, y: 0, width: 240, height: 60),
            textContainer: textContainer
        )
        textView.textContainerInset = .zero
        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: 0, length: storage.length),
            actualCharacterRange: nil
        )
        let glyphRect = layoutManager.boundingRect(
            forGlyphRange: glyphRange,
            in: textContainer
        )
        let origin = textView.textContainerOrigin
        #expect(
            textView.linkRange(
                at: NSPoint(
                    x: origin.x + glyphRect.midX,
                    y: origin.y + glyphRect.midY
                )
            ) == NSRange(location: 0, length: storage.length)
        )
        #expect(
            textView.linkRange(
                at: NSPoint(
                    x: origin.x + glyphRect.maxX + 20,
                    y: origin.y + glyphRect.midY
                )
            ) == nil
        )
        #expect(MarkdownLinkStylePolicy.normalUnderlineAlpha == 0.35)
        #expect(
            MarkdownReadingProgressPolicy.fraction(
                originY: 400,
                viewportHeight: 200,
                documentHeight: 1_000
            ) == 0.5
        )
        #expect(
            MarkdownReadingProgressPolicy.visiblePixel(
                fraction: 0.5001,
                railHeight: 800
            ) == MarkdownReadingProgressPolicy.visiblePixel(
                fraction: 0.5004,
                railHeight: 800
            )
        )
        #expect(
            MarkdownReadingProgressPolicy.fraction(
                originY: 2_000,
                viewportHeight: 200,
                documentHeight: 1_000
            ) == 1
        )
    }

#if DEBUG
    @Test("Memory fixture matches captured response shape")
    func responseMemoryFixtureShape() {
        let responses = AgentResponseMemoryFixture.responses
        let blocks = responses.flatMap { AgentMarkdownBlock.parse($0.markdown) }
        let tableRows = blocks.reduce(into: 0) { count, block in
            if case .table(_, _, let rows) = block {
                count += rows.count
            }
        }

        #expect(responses.count == 3)
        #expect(responses.reduce(0) { $0 + $1.markdown.utf8.count }
            == AgentResponseMemoryFixture.totalByteCount)
        #expect(tableRows == AgentResponseMemoryFixture.tableRowCount)
        #expect(!blocks.contains { block in
            if case .mermaid = block { return true }
            return false
        })
        #expect(AgentResponseMemoryFixture.textSelectionEnabled(
            arguments: ["Atelier", "--response-memory-fixture=selection-enabled"]
        ) == true)
        #expect(AgentResponseMemoryFixture.textSelectionEnabled(
            arguments: ["Atelier", "--response-memory-fixture=selection-disabled"]
        ) == false)
        #expect(AgentResponseMemoryFixture.scrollCycleCount(
            arguments: ["Atelier", "--response-memory-profile-scrolls=400"]
        ) == 400)
        #expect(!AgentResponseSelectionPolicy.defaultEnabled)
    }
#endif

    @Test("Response navigation stays within the selected session")
    func responseNavigationPolicy() {
        #expect(AgentResponseNavigationPolicy.previousIndex(currentIndex: nil, count: 3) == 1)
        #expect(AgentResponseNavigationPolicy.previousIndex(currentIndex: 0, count: 3) == nil)
        #expect(AgentResponseNavigationPolicy.nextIndex(currentIndex: 1, count: 3) == 2)
        #expect(AgentResponseNavigationPolicy.nextIndex(currentIndex: 2, count: 3) == nil)
        #expect(AgentResponseNavigationPolicy.nextIndex(currentIndex: nil, count: 0) == nil)
    }

    @Test("Agent response overlay supports full and half widths")
    func agentSidecarLayoutPolicy() {
        #expect(
            AgentSidecarLayoutPolicy.width(availableWidth: 720, mode: .full) == 720
        )
        #expect(
            AgentSidecarLayoutPolicy.width(availableWidth: 720, mode: .half) == 360
        )
        #expect(
            AgentSidecarLayoutPolicy.width(availableWidth: -20, mode: .full) == 0
        )
    }

    @Test("Response model exposes loading state during refresh")
    func responseLoadingState() async {
        let source = SuspendingAgentResponseSource()
        var starts = source.started.makeAsyncIterator()
        let model = AgentResponsesModel(source: source)
        let refresh = Task { await model.refresh() }

        _ = await starts.next()
        #expect(model.isRefreshing)

        await source.resume([])
        await refresh.value
        #expect(!model.isRefreshing)
    }

    @Test("Background monitoring does not show manual refresh progress")
    func backgroundMonitoringLoadingState() async {
        let source = SuspendingAgentResponseSource()
        var starts = source.started.makeAsyncIterator()
        let model = AgentResponsesModel(source: source)

        model.start()
        _ = await starts.next()
        #expect(model.isMonitoring)
        #expect(!model.isRefreshing)

        await source.resume([])
        model.stop()
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

        session.start(agentResponsesActive: false)
        session.openAgentSidecar()
        #expect(!responses.isMonitoring)
        session.activateAgentResponses()
        #expect(responses.isMonitoring)
        #expect(session.isAgentSidecarPresented)
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
        #expect(MermaidResponsePresentationPolicy.displayState(
            hasImage: false,
            error: "Invalid syntax"
        ) == .failed("Invalid syntax"))
        #expect(MermaidResponsePresentationPolicy.displayState(
            hasImage: false,
            error: nil
        ) == .loading)
        #expect(MermaidResponsePresentationPolicy.displayState(
            hasImage: true,
            error: nil
        ) == .rendered)
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

nonisolated actor SuspendingAgentResponseSource: AgentResponseSource {
    nonisolated let started: AsyncStream<Void>
    private let startedContinuation: AsyncStream<Void>.Continuation
    private var continuation: CheckedContinuation<[AgentResponse], Never>?

    init() {
        var continuation: AsyncStream<Void>.Continuation!
        started = AsyncStream { continuation = $0 }
        startedContinuation = continuation
    }

    func loadResponses() async -> [AgentResponse] {
        startedContinuation.yield()
        return await withCheckedContinuation { continuation = $0 }
    }

    func resume(_ responses: [AgentResponse]) {
        continuation?.resume(returning: responses)
        continuation = nil
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
