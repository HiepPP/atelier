import Foundation

// Value types mirroring the Watchtower VS Code extension model (src/model.ts).
// Named with a `Watchtower` prefix to avoid clashing with Swift.Task and
// SwiftUI.Section. All types are pure, Sendable, and Equatable so the parser
// can run off the main actor and the UI can diff before reloading.

nonisolated enum WatchtowerPlanStatus: Sendable, Equatable {
    case active
    case done
    case archived
    case unknown

    init(label: String) {
        switch label.trimmingCharacters(in: .whitespaces).uppercased() {
        case "ACTIVE": self = .active
        case "DONE": self = .done
        case "ARCHIVED": self = .archived
        default: self = .unknown
        }
    }
}

nonisolated enum WatchtowerTaskStatus: Sendable, Equatable {
    case todo
    case inProgress
    case blocked
    case done
    case unknown

    init(label: String) {
        switch label.trimmingCharacters(in: .whitespaces).uppercased() {
        case "DONE": self = .done
        case "IN PROGRESS", "IN_PROGRESS": self = .inProgress
        case "BLOCKED": self = .blocked
        case "TODO": self = .todo
        default: self = .unknown
        }
    }
}

nonisolated struct WatchtowerSection: Sendable, Equatable {
    let name: String
    let line: Int
}

nonisolated struct WatchtowerTask: Sendable, Equatable {
    let order: Int
    let id: String
    let title: String
    let group: String
    let status: WatchtowerTaskStatus
    let specPath: String?
    let outcomePath: String?
    let deps: String
    let notes: String
}

nonisolated struct WatchtowerPlan: Sendable, Equatable {
    let title: String
    let slug: String
    let status: WatchtowerPlanStatus
    let updated: String
    let manifestPath: String
    let tasks: [WatchtowerTask]
    let doneCount: Int
    let totalCount: Int
}

nonisolated struct WatchtowerArchivePlan: Sendable, Equatable {
    let slug: String
    let manifestPath: String
}
