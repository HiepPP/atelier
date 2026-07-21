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
