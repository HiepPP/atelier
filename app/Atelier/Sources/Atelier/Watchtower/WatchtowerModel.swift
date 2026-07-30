import Foundation
import Observation

// Dashboard grouping for tracker tasks, mirroring the extension's
// Active / Blocked / Todo / Done sections. Unknown status maps to no group.
nonisolated enum WatchtowerTaskGroup: CaseIterable, Sendable {
    case active
    case blocked
    case todo
    case done

    init?(status: WatchtowerTaskStatus) {
        switch status {
        case .inProgress: self = .active
        case .blocked: self = .blocked
        case .todo: self = .todo
        case .done: self = .done
        case .unknown: return nil
        }
    }
}

nonisolated struct WatchtowerLoad: Sendable {
    let plan: WatchtowerPlan?
    let archive: [WatchtowerArchivePlan]
    let contextPath: String?
}

// Reads the active Watchtower plan from a workspace root via WatchtowerParser
// and exposes progress, counts, tasks, and archive. Read-only: it never writes
// plan files. Diffs by Equatable so observers only update on a real change.
@Observable
final class WatchtowerModel {
    private(set) var rootDir: String?
    private(set) var plan: WatchtowerPlan?
    private(set) var archive: [WatchtowerArchivePlan] = []
    // Resolved on refresh, never in a view body, so the panel never stats the disk while drawing.
    private(set) var contextPath: String?

    // Loaders are injected for deterministic tests; defaults use the parser.
    // `@Sendable` because loading runs off the main actor.
    @ObservationIgnored private let planLoader: @Sendable (String) -> WatchtowerPlan?
    @ObservationIgnored private let archiveLoader: @Sendable (String) -> [WatchtowerArchivePlan]
    @ObservationIgnored private var loadGeneration: UInt64 = 0

    /// Construction never touches the disk. Callers set a root, which loads.
    init(
        rootDir: String? = nil,
        planLoader: @Sendable @escaping (String) -> WatchtowerPlan? = {
            WatchtowerParser.readPlan(rootDir: $0)
        },
        archiveLoader: @Sendable @escaping (String) -> [WatchtowerArchivePlan] = {
            WatchtowerParser.listArchive(rootDir: $0)
        }
    ) {
        self.rootDir = rootDir
        self.planLoader = planLoader
        self.archiveLoader = archiveLoader
    }

    // MARK: - Loading

    @discardableResult
    func setRoot(_ root: String) async -> Bool {
        if root != rootDir { rootDir = root }
        return await refresh()
    }

    /// Drops the root and every loaded value. Synchronous on purpose: teardown
    /// must not depend on a task that may never get to run.
    @discardableResult
    func clear() -> Bool {
        loadGeneration &+= 1
        rootDir = nil
        return apply(plan: nil, archive: [], contextPath: nil)
    }

    /// Reads the plan, archive, and context path off the main actor. The walk
    /// stats one directory per archive entry and reads every task spec, so on
    /// the main actor it blocked the UI for the whole traversal.
    @discardableResult
    func refresh() async -> Bool {
        guard let root = rootDir else {
            return apply(plan: nil, archive: [], contextPath: nil)
        }
        loadGeneration &+= 1
        let generation = loadGeneration
        let planLoader = planLoader
        let archiveLoader = archiveLoader
        let loaded = await Task.detached(priority: .utility) {
            WatchtowerLoad(
                plan: planLoader(root),
                archive: archiveLoader(root),
                contextPath: Self.existingContextPath(root: root)
            )
        }.value
        // A newer load, a cleared root, or a different root started while this
        // walk ran: dropping the result keeps the newest value applied.
        guard generation == loadGeneration, rootDir == root else { return false }
        return apply(
            plan: loaded.plan,
            archive: loaded.archive,
            contextPath: loaded.contextPath
        )
    }

    // Assign only changed values so @Observable does not fire on a no-op refresh.
    private func apply(
        plan newPlan: WatchtowerPlan?,
        archive newArchive: [WatchtowerArchivePlan],
        contextPath newContextPath: String?
    ) -> Bool {
        var changed = false
        if newPlan != plan {
            plan = newPlan
            changed = true
        }
        if newArchive != archive {
            archive = newArchive
            changed = true
        }
        if newContextPath != contextPath {
            contextPath = newContextPath
            changed = true
        }
        return changed
    }

    // nil when the workspace has no watchtower/CONTEXT.md, so the panel can disable the action
    // instead of opening a path that does not exist.
    nonisolated private static func existingContextPath(root: String) -> String? {
        let path = ((root as NSString).appendingPathComponent("watchtower") as NSString)
            .appendingPathComponent("CONTEXT.md")
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    // MARK: - Derived state

    var hasPlan: Bool { plan != nil }

    var title: String { plan?.title ?? "" }

    var tasks: [WatchtowerTask] { plan?.tasks ?? [] }

    var totalCount: Int { plan?.totalCount ?? 0 }

    var doneCount: Int { plan?.doneCount ?? 0 }

    var remaining: Int { totalCount - doneCount }

    // Fraction done in 0...1. Zero when the plan has no tasks.
    var progress: Double {
        totalCount == 0 ? 0 : Double(doneCount) / Double(totalCount)
    }

    // First in-progress task by order, matching the extension summary.
    var inProgressId: String? {
        tasks
            .filter { $0.status == .inProgress }
            .sorted { $0.order < $1.order }
            .first?
            .id
    }

    var blockedIds: [String] {
        tasks.filter { $0.status == .blocked }.map(\.id)
    }

    var hasBlocked: Bool { !blockedIds.isEmpty }

    func tasks(in group: WatchtowerTaskGroup) -> [WatchtowerTask] {
        tasks.filter { WatchtowerTaskGroup(status: $0.status) == group }
    }
}
