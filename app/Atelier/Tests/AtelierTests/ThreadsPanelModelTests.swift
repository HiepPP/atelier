import Foundation
import Testing
@testable import Atelier

@Suite("Threads panel model")
@MainActor
struct ThreadsPanelModelTests {
    @Test("Agent transitions from running to done without timestamp churn")
    func runningToDone() throws {
        let model = ThreadsPanelModel()
        let terminalID = UUID()
        let startedAt = Date(timeIntervalSince1970: 100)
        let later = Date(timeIntervalSince1970: 200)

        model.refresh(
            snapshots: [snapshot(id: terminalID, agentName: "claude")],
            now: startedAt
        )
        let running = try #require(model.groups.first?.threads.first)
        #expect(running.status == .running)
        #expect(running.startedAt == startedAt)
        #expect(running.finishedAt == nil)

        let unchangedGroups = model.groups
        model.refresh(
            snapshots: [snapshot(id: terminalID, agentName: "claude")],
            now: later
        )
        #expect(model.groups == unchangedGroups)

        model.refresh(
            snapshots: [snapshot(id: terminalID, agentName: nil)],
            now: later
        )
        let done = try #require(model.groups.first?.threads.first)
        #expect(done.status == .done)
        #expect(done.startedAt == startedAt)
        #expect(done.finishedAt == later)
    }

    @Test("Closing a terminal removes its thread")
    func removedTerminalDropsThread() {
        let model = ThreadsPanelModel()
        model.refresh(
            snapshots: [snapshot(agentName: "codex")],
            now: Date(timeIntervalSince1970: 100)
        )
        #expect(model.groups.first?.threads.count == 1)

        model.refresh(snapshots: [], now: Date(timeIntervalSince1970: 200))
        #expect(model.groups.isEmpty)
    }

    @Test("Shell-only workspace keeps an empty group")
    func shellOnlyWorkspaceKeepsGroup() throws {
        let model = ThreadsPanelModel()
        model.refresh(
            snapshots: [snapshot(agentName: nil)],
            now: Date(timeIntervalSince1970: 100)
        )

        let group = try #require(model.groups.first)
        #expect(group.name == "Atelier")
        #expect(group.threads.isEmpty)
    }

    @Test("A shell mark dates the done row instead of the poll time")
    func shellMarkDatesDoneRow() throws {
        let model = ThreadsPanelModel()
        let terminalID = UUID()
        let startedAt = Date(timeIntervalSince1970: 100)
        let exitedAt = Date(timeIntervalSince1970: 150)
        // Far later than the exit: stands in for a poll delayed by occlusion.
        let polledAt = Date(timeIntervalSince1970: 900)

        model.refresh(snapshots: [snapshot(id: terminalID, agentName: "claude")], now: startedAt)
        model.recordShellCommandFinished(terminalID: terminalID, at: exitedAt)
        model.refresh(snapshots: [snapshot(id: terminalID, agentName: nil)], now: polledAt)

        let done = try #require(model.groups.first?.threads.first)
        #expect(done.status == .done)
        #expect(done.finishedAt == exitedAt)
    }

    @Test("A mark seen while the agent keeps running does not date a later run")
    func markDuringRunIsDiscarded() throws {
        let model = ThreadsPanelModel()
        let terminalID = UUID()
        let startedAt = Date(timeIntervalSince1970: 100)
        let subcommandAt = Date(timeIntervalSince1970: 120)
        let polledAt = Date(timeIntervalSince1970: 300)

        model.refresh(snapshots: [snapshot(id: terminalID, agentName: "claude")], now: startedAt)
        model.recordShellCommandFinished(terminalID: terminalID, at: subcommandAt)
        // The agent is still there, so the mark belonged to another command.
        model.refresh(snapshots: [snapshot(id: terminalID, agentName: "claude")], now: subcommandAt)
        model.refresh(snapshots: [snapshot(id: terminalID, agentName: nil)], now: polledAt)

        let done = try #require(model.groups.first?.threads.first)
        #expect(done.finishedAt == polledAt)
    }

    @Test("Without a shell mark the poll time still dates the done row")
    func pollTimeRemainsTheFallback() throws {
        let model = ThreadsPanelModel()
        let terminalID = UUID()
        let polledAt = Date(timeIntervalSince1970: 300)

        model.refresh(
            snapshots: [snapshot(id: terminalID, agentName: "codex")],
            now: Date(timeIntervalSince1970: 100)
        )
        model.refresh(snapshots: [snapshot(id: terminalID, agentName: nil)], now: polledAt)

        let done = try #require(model.groups.first?.threads.first)
        #expect(done.finishedAt == polledAt)
    }

    @Test("A mark outside the run window falls back to the poll time")
    func outOfRangeMarkFallsBack() {
        let startedAt = Date(timeIntervalSince1970: 100)
        let now = Date(timeIntervalSince1970: 300)

        // Before the run started.
        #expect(
            ThreadsPanelModel.finishTime(
                shellReported: Date(timeIntervalSince1970: 50),
                startedAt: startedAt,
                now: now
            ) == now
        )
        // After the poll.
        #expect(
            ThreadsPanelModel.finishTime(
                shellReported: Date(timeIntervalSince1970: 500),
                startedAt: startedAt,
                now: now
            ) == now
        )
        // Absent.
        #expect(
            ThreadsPanelModel.finishTime(
                shellReported: nil,
                startedAt: startedAt,
                now: now
            ) == now
        )
        // Inside the window.
        let exitedAt = Date(timeIntervalSince1970: 200)
        #expect(
            ThreadsPanelModel.finishTime(
                shellReported: exitedAt,
                startedAt: startedAt,
                now: now
            ) == exitedAt
        )
    }

    private func snapshot(
        id: UUID = UUID(),
        agentName: String?
    ) -> TerminalSnapshot {
        TerminalSnapshot(
            terminalID: id,
            title: "Terminal 1",
            workspaceID: "/tmp/Atelier",
            workspaceName: "Atelier",
            agentName: agentName
        )
    }
}
