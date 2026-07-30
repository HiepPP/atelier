import Foundation
import Testing
@testable import Atelier

/// Loaders run off the main actor, so a loader the test mutates needs real
/// synchronization rather than a captured `var`.
private nonisolated final class PlanBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: WatchtowerPlan?

    init(_ plan: WatchtowerPlan?) { storage = plan }

    var current: WatchtowerPlan? {
        get { lock.withLock { storage } }
        set { lock.withLock { storage = newValue } }
    }
}

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
    func loadsPlanExposesCountsAndProgress() async {
        let loaded = plan(demoContent())
        let model = WatchtowerModel(
            rootDir: "/ws",
            planLoader: { _ in loaded },
            archiveLoader: { _ in [] }
        )
        await model.refresh()

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

    @Test("Construction never loads; the root has to be set")
    func constructionDoesNotLoad() async {
        let loaded = plan(demoContent())
        let model = WatchtowerModel(
            rootDir: "/ws",
            planLoader: { _ in loaded },
            archiveLoader: { _ in [] }
        )

        #expect(!model.hasPlan)
        await model.refresh()
        #expect(model.hasPlan)
    }

    @Test("Groups tasks by status")
    func groupsTasksByStatus() async {
        let loaded = plan(demoContent())
        let model = WatchtowerModel(
            rootDir: "/ws",
            planLoader: { _ in loaded },
            archiveLoader: { _ in [] }
        )
        await model.refresh()

        #expect(model.tasks(in: .done).map(\.id) == ["TASK-001"])
        #expect(model.tasks(in: .active).map(\.id) == ["TASK-002"])
        #expect(model.tasks(in: .blocked).map(\.id) == ["TASK-003"])
        #expect(model.tasks(in: .todo).map(\.id) == ["TASK-004"])
    }

    // MARK: - Diff behaviour

    @Test("Reapplying identical plan reports no change")
    func reapplyingIdenticalReportsNoChange() async {
        let current = plan(demoContent())
        let model = WatchtowerModel(
            rootDir: "/ws",
            planLoader: { _ in current },
            archiveLoader: { _ in [] }
        )

        #expect(await model.refresh())
        // A second identical load must not fire observers.
        #expect(!(await model.refresh()))
    }

    @Test("Changed plan reports change and updates counts")
    func changedPlanReportsChange() async {
        let plans = PlanBox(plan(demoContent()))
        let model = WatchtowerModel(
            rootDir: "/ws",
            planLoader: { _ in plans.current },
            archiveLoader: { _ in [] }
        )
        await model.refresh()
        #expect(model.doneCount == 1)

        plans.current = plan(demoContent(task4: "DONE"))
        #expect(await model.refresh())
        #expect(model.doneCount == 2)
        #expect(model.tasks(in: .todo).isEmpty)
    }

    @Test("clear() drops plan and archive")
    func clearDropsPlanAndArchive() async {
        let loaded = plan(demoContent())
        let archived = [WatchtowerArchivePlan(slug: "a", manifestPath: "/ws/watchtower/archive/a/NEXT.md")]
        let model = WatchtowerModel(
            rootDir: "/ws",
            planLoader: { _ in loaded },
            archiveLoader: { _ in archived }
        )
        await model.refresh()
        #expect(model.hasPlan)
        #expect(!model.archive.isEmpty)

        #expect(model.clear())
        #expect(!model.hasPlan)
        #expect(model.archive.isEmpty)
        #expect(model.totalCount == 0)
        #expect(model.progress == 0)

        #expect(!model.clear())
    }

    /// The walk runs off the main actor, so a root that changes mid-flight must
    /// not let a stale result overwrite the newer one.
    @Test("A cleared root discards an in-flight load")
    func clearedRootDiscardsInFlightLoad() async {
        let loaded = plan(demoContent())
        let model = WatchtowerModel(
            rootDir: "/ws",
            planLoader: { _ in loaded },
            archiveLoader: { _ in [] }
        )

        async let refreshed = model.refresh()
        model.clear()

        #expect(!(await refreshed))
        #expect(!model.hasPlan)
    }

    @Test("Archive is exposed from the loader")
    func archiveExposed() async {
        let archived = [
            WatchtowerArchivePlan(slug: "20260202-b", manifestPath: "/ws/watchtower/archive/20260202-b/NEXT.md"),
            WatchtowerArchivePlan(slug: "20260101-a", manifestPath: "/ws/watchtower/archive/20260101-a/NEXT.md"),
        ]
        let model = WatchtowerModel(
            rootDir: "/ws",
            planLoader: { _ in nil },
            archiveLoader: { _ in archived }
        )
        await model.refresh()
        #expect(model.archive.map(\.slug) == ["20260202-b", "20260101-a"])
    }

    // MARK: - Default loader end-to-end

    @Test("Default loader reads the plan from disk via the parser")
    func defaultLoaderReadsFromDisk() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let tasksDir = ((root as NSString).appendingPathComponent("watchtower") as NSString).appendingPathComponent("tasks")
        try FileManager.default.createDirectory(atPath: tasksDir, withIntermediateDirectories: true)
        let manifest = ((root as NSString).appendingPathComponent("watchtower") as NSString).appendingPathComponent("NEXT.md")
        try demoContent().write(toFile: manifest, atomically: true, encoding: .utf8)

        let model = WatchtowerModel()
        #expect(!model.hasPlan)

        #expect(await model.setRoot(root))
        #expect(model.title == "Demo")
        #expect(model.totalCount == 4)
        #expect(model.inProgressId == "TASK-002")
        #expect(model.tasks.first?.specPath == (tasksDir as NSString).appendingPathComponent("TASK-001-a.md"))
    }
}
