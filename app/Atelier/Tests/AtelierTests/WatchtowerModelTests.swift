import Foundation
import Testing
@testable import Atelier

@Suite("Watchtower model")
@MainActor
struct WatchtowerModelTests {

    // MARK: - Helpers

    private func plan(_ content: String) -> WatchtowerPlan {
        WatchtowerParser.parsePlanContent(content, manifestPath: "/ws/watchtower/NEXT.md")
    }

    private func demoContent(task4 status: String = "TODO") -> String {
        [
            "## Current Active Plan",
            "",
            "Title: Demo",
            "Slug: 20260101-demo",
            "Status: ACTIVE",
            "Updated: 2026-01-01",
            "",
            "## Tracker",
            "",
            "| Order | TASK | Group | Status | Spec | Deps | Context | Notes |",
            "|---|---|---|---|---|---|---|---|",
            "| 1 | TASK-001 A | g | DONE | watchtower/tasks/TASK-001-a.md | - | - | n |",
            "| 2 | TASK-002 B | g | IN PROGRESS | watchtower/tasks/TASK-002-b.md | - | - | n |",
            "| 3 | TASK-003 C | g | BLOCKED | watchtower/tasks/TASK-003-c.md | - | - | n |",
            "| 4 | TASK-004 D | g | \(status) | watchtower/tasks/TASK-004-d.md | TASK-003 | - | n |",
        ].joined(separator: "\n")
    }

    private func makeTempDir() throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("watchtower-model-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }

    // MARK: - Derived state

    @Test("Loads plan and exposes counts and progress")
    func loadsPlanExposesCountsAndProgress() {
        let loaded = plan(demoContent())
        let model = WatchtowerModel(rootDir: "/ws", planLoader: { _ in loaded }, archiveLoader: { _ in [] })

        #expect(model.hasPlan)
        #expect(model.title == "Demo")
        #expect(model.totalCount == 4)
        #expect(model.doneCount == 1)
        #expect(model.remaining == 3)
        #expect(abs(model.progress - 0.25) < 1e-9)
        #expect(model.inProgressId == "TASK-002")
        #expect(model.blockedIds == ["TASK-003"])
        #expect(model.hasBlocked)
    }

    @Test("Groups tasks by status")
    func groupsTasksByStatus() {
        let loaded = plan(demoContent())
        let model = WatchtowerModel(rootDir: "/ws", planLoader: { _ in loaded }, archiveLoader: { _ in [] })

        #expect(model.tasks(in: .done).map(\.id) == ["TASK-001"])
        #expect(model.tasks(in: .active).map(\.id) == ["TASK-002"])
        #expect(model.tasks(in: .blocked).map(\.id) == ["TASK-003"])
        #expect(model.tasks(in: .todo).map(\.id) == ["TASK-004"])
    }

    // MARK: - Diff behaviour

    @Test("Reapplying identical plan reports no change")
    func reapplyingIdenticalReportsNoChange() {
        let current = plan(demoContent())
        let model = WatchtowerModel(rootDir: "/ws", planLoader: { _ in current }, archiveLoader: { _ in [] })
        // init already applied the plan; a second identical load is a no-op.
        #expect(!model.refresh())
    }

    @Test("Changed plan reports change and updates counts")
    func changedPlanReportsChange() {
        var current = plan(demoContent())
        let model = WatchtowerModel(rootDir: "/ws", planLoader: { _ in current }, archiveLoader: { _ in [] })
        #expect(model.doneCount == 1)

        current = plan(demoContent(task4: "DONE"))
        #expect(model.refresh())
        #expect(model.doneCount == 2)
        #expect(model.tasks(in: .todo).isEmpty)
    }

    @Test("setRoot(nil) clears plan and archive")
    func setRootNilClears() {
        let loaded = plan(demoContent())
        let archived = [WatchtowerArchivePlan(slug: "a", manifestPath: "/ws/watchtower/archive/a/NEXT.md")]
        let model = WatchtowerModel(rootDir: "/ws", planLoader: { _ in loaded }, archiveLoader: { _ in archived })
        #expect(model.hasPlan)
        #expect(!model.archive.isEmpty)

        #expect(model.setRoot(nil))
        #expect(!model.hasPlan)
        #expect(model.archive.isEmpty)
        #expect(model.totalCount == 0)
        #expect(model.progress == 0)

        #expect(!model.setRoot(nil))
    }

    @Test("Archive is exposed from the loader")
    func archiveExposed() {
        let archived = [
            WatchtowerArchivePlan(slug: "20260202-b", manifestPath: "/ws/watchtower/archive/20260202-b/NEXT.md"),
            WatchtowerArchivePlan(slug: "20260101-a", manifestPath: "/ws/watchtower/archive/20260101-a/NEXT.md"),
        ]
        let model = WatchtowerModel(rootDir: "/ws", planLoader: { _ in nil }, archiveLoader: { _ in archived })
        #expect(model.archive.map(\.slug) == ["20260202-b", "20260101-a"])
    }

    // MARK: - Default loader end-to-end

    @Test("Default loader reads the plan from disk via the parser")
    func defaultLoaderReadsFromDisk() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let tasksDir = ((root as NSString).appendingPathComponent("watchtower") as NSString).appendingPathComponent("tasks")
        try FileManager.default.createDirectory(atPath: tasksDir, withIntermediateDirectories: true)
        let manifest = ((root as NSString).appendingPathComponent("watchtower") as NSString).appendingPathComponent("NEXT.md")
        try demoContent().write(toFile: manifest, atomically: true, encoding: .utf8)

        let model = WatchtowerModel()
        #expect(!model.hasPlan)

        #expect(model.setRoot(root))
        #expect(model.title == "Demo")
        #expect(model.totalCount == 4)
        #expect(model.inProgressId == "TASK-002")
        #expect(model.tasks.first?.specPath == (tasksDir as NSString).appendingPathComponent("TASK-001-a.md"))
    }
}
