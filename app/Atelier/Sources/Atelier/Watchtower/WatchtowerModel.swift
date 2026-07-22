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

// Reads the active Watchtower plan from a workspace root via WatchtowerParser
// and exposes progress, counts, tasks, and archive. Read-only: it never writes
// plan files. Diffs by Equatable so observers only update on a real change.
@Observable
final class WatchtowerModel {
    private(set) var rootDir: String?
    private(set) var plan: WatchtowerPlan?
    private(set) var archive: [WatchtowerArchivePlan] = []

    // Loaders are injected for deterministic tests; defaults use the parser.
    @ObservationIgnored private let planLoader: (String) -> WatchtowerPlan?
    @ObservationIgnored private let archiveLoader: (String) -> [WatchtowerArchivePlan]

    init(
        rootDir: String? = nil,
        planLoader: @escaping (String) -> WatchtowerPlan? = { WatchtowerParser.readPlan(rootDir: $0) },
        archiveLoader: @escaping (String) -> [WatchtowerArchivePlan] = { WatchtowerParser.listArchive(rootDir: $0) }
    ) {
        self.rootDir = rootDir
        self.planLoader = planLoader
        self.archiveLoader = archiveLoader
        _ = refresh()
    }

    // MARK: - Loading

    @discardableResult
    func setRoot(_ root: String?) -> Bool {
        if root != rootDir { rootDir = root }
        return refresh()
    }

    @discardableResult
    func refresh() -> Bool {
        guard let root = rootDir else {
            return apply(plan: nil, archive: [])
        }
        return apply(plan: planLoader(root), archive: archiveLoader(root))
    }

    // Assign only changed values so @Observable does not fire on a no-op refresh.
    private func apply(plan newPlan: WatchtowerPlan?, archive newArchive: [WatchtowerArchivePlan]) -> Bool {
        var changed = false
        if newPlan != plan {
            plan = newPlan
            changed = true
        }
        if newArchive != archive {
            archive = newArchive
            changed = true
        }
        return changed
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
