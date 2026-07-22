import Foundation
import Testing
@testable import Atelier

@Suite("Watchtower parser")
@MainActor
struct WatchtowerParserTests {

    // MARK: - Fixtures

    private func fixture(_ name: String) throws -> String {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "md", subdirectory: "Fixtures"),
            "missing fixture \(name)"
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func makeTempDir() throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("watchtower-parser-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }

    // MARK: - Status mapping

    @Test("Task status maps known labels")
    func taskStatusMapsKnownLabels() {
        #expect(WatchtowerTaskStatus(label: "DONE") == .done)
        #expect(WatchtowerTaskStatus(label: "IN PROGRESS") == .inProgress)
        #expect(WatchtowerTaskStatus(label: "in progress") == .inProgress)
        #expect(WatchtowerTaskStatus(label: "BLOCKED") == .blocked)
        #expect(WatchtowerTaskStatus(label: "TODO") == .todo)
        #expect(WatchtowerTaskStatus(label: "weird") == .unknown)
    }

    @Test("Plan status maps known labels")
    func planStatusMapsKnownLabels() {
        #expect(WatchtowerPlanStatus(label: "ACTIVE") == .active)
        #expect(WatchtowerPlanStatus(label: "archived") == .archived)
        #expect(WatchtowerPlanStatus(label: "DONE") == .done)
        #expect(WatchtowerPlanStatus(label: "") == .unknown)
    }

    // MARK: - Plan header + tracker

    @Test("parsePlanContent reads header and tracker")
    func parsePlanContentReadsHeaderAndTracker() throws {
        let plan = WatchtowerParser.parsePlanContent(try fixture("sample-NEXT"), manifestPath: "/ws/watchtower/NEXT.md")
        #expect(plan.title == "Gacha Size Quiz")
        #expect(plan.slug == "20260620-gacha-size-quiz")
        #expect(plan.status == .archived)
        #expect(plan.totalCount == 4)
        #expect(plan.doneCount == 3)

        #expect(plan.tasks.count == 4)
        #expect(plan.tasks.map(\.status) == [.done, .done, .done, .blocked])

        let first = plan.tasks[0]
        #expect(first.id == "TASK-001")
        #expect(first.title == "Build quiz state and markup shell")
        #expect(first.order == 1)
        #expect(first.group == "standalone")
        #expect(!first.notes.isEmpty)
        #expect(first.specPath == "/ws/watchtower/tasks/TASK-001-build-quiz-state-and-markup-shell.md")

        let fourth = plan.tasks[3]
        #expect(fourth.id == "TASK-004")
        #expect(fourth.specPath == "/ws/watchtower/tasks/TASK-004-integrate-responsive-flow-and-qa.md")
    }

    // MARK: - Task spec sections

    @Test("parseTaskFile finds sections and outcome status")
    func parseTaskFileFindsSectionsAndOutcome() throws {
        let result = WatchtowerParser.parseTaskFile(try fixture("sample-task"))
        #expect(result.sections.map(\.name) == ["Brief", "Verify", "Outcome"])
        #expect(result.sections.allSatisfy { $0.line >= 0 })
        #expect(result.sections[0].line < result.sections[1].line)
        #expect(result.sections[1].line < result.sections[2].line)
        #expect(result.outcomeStatus == .blocked)
    }

    @Test("parseTaskFile returns nil outcome when absent")
    func parseTaskFileReturnsNilOutcomeWhenAbsent() {
        let result = WatchtowerParser.parseTaskFile("# TASK-009 X\n\n## Brief\n\nGoal: x.\n")
        #expect(result.outcomeStatus == nil)
        #expect(result.sections.map(\.name) == ["Brief"])
    }

    @Test("readTaskFile returns empty result for a missing file")
    func readTaskFileMissing() {
        let result = WatchtowerParser.readTaskFile("/does/not/exist.md")
        #expect(result.sections.isEmpty)
        #expect(result.outcomeStatus == nil)
    }

    // MARK: - Spec cell resolution

    @Test("parsePlanContent resolves markdown-link Spec cells")
    func parsePlanContentResolvesLinkSpec() {
        let content = [
            "# NEXT",
            "",
            "## Current Active Plan",
            "",
            "- Title: Link Form",
            "- Slug: 20260101-link-form",
            "- Status: ACTIVE",
            "- Updated: 2026-01-01",
            "",
            "## Tracker",
            "",
            "| Order | TASK | Group | Status | Spec | Deps | Context | Notes |",
            "|-------|------|-------|--------|------|------|---------|-------|",
            "| 1 | TASK-001 Foo | A | IN PROGRESS | [watchtower/tasks/TASK-001-foo.md](watchtower/tasks/TASK-001-foo.md) | - | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | a note |",
            "",
            "## Handoff",
            "",
            "- Next action: x",
        ].joined(separator: "\n")
        let plan = WatchtowerParser.parsePlanContent(content, manifestPath: "/ws/watchtower/NEXT.md")
        #expect(plan.status == .active)
        #expect(plan.totalCount == 1)
        #expect(plan.tasks[0].status == .inProgress)
        #expect(plan.tasks[0].group == "A")
        #expect(plan.tasks[0].specPath == "/ws/watchtower/tasks/TASK-001-foo.md")
        #expect(plan.tasks[0].outcomePath == nil)
    }

    @Test("parsePlanContent derives task id from Spec when TASK cell is title only")
    func parsePlanContentDerivesIdFromSpec() {
        let content = [
            "# NEXT",
            "",
            "## Current Active Plan",
            "",
            "- Title: Title Only",
            "- Slug: 20260101-title-only",
            "- Status: ACTIVE",
            "- Updated: 2026-01-01",
            "",
            "## Tracker",
            "",
            "| Order | TASK | Group | Status | Spec | Deps | Context | Notes |",
            "|-------|------|-------|--------|------|------|---------|-------|",
            "| 4 | Show task code in rows | A | TODO | [watchtower/tasks/TASK-004-show-task-code-in-rows.md](watchtower/tasks/TASK-004-show-task-code-in-rows.md) | - | - | title-only cell |",
        ].joined(separator: "\n")
        let plan = WatchtowerParser.parsePlanContent(content, manifestPath: "/ws/watchtower/NEXT.md")
        #expect(plan.tasks[0].id == "TASK-004")
        #expect(plan.tasks[0].title == "Show task code in rows")
        #expect(plan.tasks[0].specPath == "/ws/watchtower/tasks/TASK-004-show-task-code-in-rows.md")
    }

    @Test("parsePlanContent falls back to padded order when TASK cell and Spec lack id")
    func parsePlanContentFallsBackToPaddedOrder() {
        let content = [
            "# NEXT",
            "",
            "## Current Active Plan",
            "",
            "- Title: Order Fallback",
            "- Slug: 20260101-order-fallback",
            "- Status: ACTIVE",
            "- Updated: 2026-01-01",
            "",
            "## Tracker",
            "",
            "| Order | TASK | Group | Status | Spec | Deps | Context | Notes |",
            "|-------|------|-------|--------|------|------|---------|-------|",
            "| 5 | Row title | A | TODO | watchtower/tasks/row-title.md | - | - | no code |",
        ].joined(separator: "\n")
        let plan = WatchtowerParser.parsePlanContent(content, manifestPath: "/ws/watchtower/NEXT.md")
        #expect(plan.tasks[0].id == "TASK-005")
        #expect(plan.tasks[0].title == "Row title")
    }

    @Test("parsePlanContent resolves existing outcome files beside TASK specs")
    func parsePlanContentResolvesOutcomeFile() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let tasksDir = ((root as NSString).appendingPathComponent("watchtower") as NSString).appendingPathComponent("tasks")
        try FileManager.default.createDirectory(atPath: tasksDir, withIntermediateDirectories: true)
        let outcome = (tasksDir as NSString).appendingPathComponent("TASK-001-outcome.md")
        try "# Outcome\n".write(toFile: outcome, atomically: true, encoding: .utf8)

        let content = [
            "# NEXT",
            "",
            "## Current Active Plan",
            "",
            "- Title: Outcome File",
            "- Slug: 20260101-outcome-file",
            "- Status: ACTIVE",
            "- Updated: 2026-01-01",
            "",
            "## Tracker",
            "",
            "| Order | TASK | Group | Status | Spec | Deps | Context | Notes |",
            "|-------|------|-------|--------|------|------|---------|-------|",
            "| 1 | TASK-001 Foo | A | DONE | watchtower/tasks/TASK-001-foo.md | - | - | done |",
        ].joined(separator: "\n")
        let manifest = ((root as NSString).appendingPathComponent("watchtower") as NSString).appendingPathComponent("NEXT.md")
        let plan = WatchtowerParser.parsePlanContent(content, manifestPath: manifest)
        #expect(plan.tasks[0].outcomePath == outcome)
    }

    @Test("parsePlanContent returns no tasks when Tracker section is absent")
    func parsePlanContentNoTracker() {
        let content = "# NEXT\n\n## Current Active Plan\n\nTitle: Empty\nStatus: ACTIVE\n\n## Handoff\n\n- none\n"
        let plan = WatchtowerParser.parsePlanContent(content, manifestPath: "/ws/watchtower/NEXT.md")
        #expect(plan.title == "Empty")
        #expect(plan.totalCount == 0)
        #expect(plan.tasks.isEmpty)
    }

    @Test("parsePlanContent still parses legacy TODO plans")
    func parsePlanContentLegacyTodo() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let todosDir = ((root as NSString).appendingPathComponent("watchtower") as NSString).appendingPathComponent("todos")
        try FileManager.default.createDirectory(atPath: todosDir, withIntermediateDirectories: true)

        let content = [
            "# NEXT",
            "",
            "## Current Active Plan",
            "",
            "- Title: Legacy",
            "- Slug: 20260101-legacy",
            "- Status: ACTIVE",
            "- Updated: 2026-01-01",
            "",
            "## Tracker",
            "",
            "| Order | TODO | Group | Status | Spec | Deps | Context | Notes |",
            "|-------|------|-------|--------|------|------|---------|-------|",
            "| 1 | TODO-001 Foo | A | TODO | watchtower/todos/TODO-001-foo.md | - | - | legacy |",
        ].joined(separator: "\n")
        let manifest = ((root as NSString).appendingPathComponent("watchtower") as NSString).appendingPathComponent("NEXT.md")
        let plan = WatchtowerParser.parsePlanContent(content, manifestPath: manifest)
        #expect(plan.totalCount == 1)
        #expect(plan.tasks[0].id == "TODO-001")
        #expect(plan.tasks[0].specPath == (todosDir as NSString).appendingPathComponent("TODO-001-foo.md"))
    }

    // MARK: - Archive

    @Test("listArchive returns archived plans sorted by slug descending")
    func listArchiveSortedDescending() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let archive = ((root as NSString).appendingPathComponent("watchtower") as NSString).appendingPathComponent("archive")
        let older = (archive as NSString).appendingPathComponent("20260101-older")
        let newer = (archive as NSString).appendingPathComponent("20260202-newer")
        let empty = (archive as NSString).appendingPathComponent("20260303-no-manifest")
        try FileManager.default.createDirectory(atPath: older, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: newer, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: empty, withIntermediateDirectories: true)
        try "# NEXT\n".write(toFile: (older as NSString).appendingPathComponent("NEXT.md"), atomically: true, encoding: .utf8)
        try "# NEXT\n".write(toFile: (newer as NSString).appendingPathComponent("NEXT.md"), atomically: true, encoding: .utf8)

        let plans = WatchtowerParser.listArchive(rootDir: root)
        #expect(plans.map(\.slug) == ["20260202-newer", "20260101-older"])
        #expect(plans.first?.manifestPath == (newer as NSString).appendingPathComponent("NEXT.md"))
    }

    @Test("listArchive returns empty when no archive directory")
    func listArchiveEmpty() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: root) }
        #expect(WatchtowerParser.listArchive(rootDir: root).isEmpty)
    }
}
