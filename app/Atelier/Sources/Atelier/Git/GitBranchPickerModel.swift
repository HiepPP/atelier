import Foundation
import Observation
import OSLog

/// One step of the picker. `selectingRef` is the entry stage; the other three
/// are the second half of a two-step action, so Escape steps back to
/// `selectingRef` instead of closing the whole picker.
nonisolated enum GitBranchPickerStage: Equatable, Sendable {
    case selectingRef
    case selectingBase
    case namingBranch(base: String?)
    case selectingDetachRef

    var prompt: String {
        switch self {
        case .selectingRef: "Select a branch or tag to checkout"
        case .selectingBase: "Select a ref to branch from"
        case .namingBranch(let base):
            base.map { "Name the branch created from \($0)" } ?? "Name the new branch"
        case .selectingDetachRef: "Select a ref to checkout detached"
        }
    }

    var showsActions: Bool { self == .selectingRef }

    var isNaming: Bool {
        if case .namingBranch = self { return true }
        return false
    }
}

nonisolated enum GitBranchPickerAction: String, Identifiable, CaseIterable, Sendable {
    case createBranch
    case createBranchFrom
    case checkoutDetached

    var id: String { rawValue }

    var title: String {
        switch self {
        case .createBranch: "Create new branch..."
        case .createBranchFrom: "Create new branch from..."
        case .checkoutDetached: "Checkout detached..."
        }
    }

    var systemImage: String {
        switch self {
        case .createBranch, .createBranchFrom: "plus"
        case .checkoutDetached: "arrow.triangle.branch"
        }
    }
}

@MainActor
@Observable
final class GitBranchPickerModel {
    private(set) var isPresented = false
    private(set) var stage = GitBranchPickerStage.selectingRef
    private(set) var refs: [GitRef] = []
    private(set) var isLoading = false
    private(set) var isRunningAction = false
    private(set) var errorMessage: String?
    var query = ""
    var selectedID: String?

    /// Called after a checkout, branch creation, or detach changes HEAD.
    var onRefChanged: () -> Void = {}

    private let workspacePath: String
    private let service: GitService
    private var loadTask: Task<Void, Never>?
    private var actionTask: Task<Void, Never>?
    private var loadID = UUID()

    init(workspacePath: String, service: GitService) {
        self.workspacePath = workspacePath
        self.service = service
    }

    var visibleActions: [GitBranchPickerAction] {
        guard stage.showsActions else { return [] }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return GitBranchPickerAction.allCases }
        return GitBranchPickerAction.allCases.filter {
            $0.title.lowercased().contains(needle)
        }
    }

    var visibleRefs: [GitRef] {
        guard !stage.isNaming else { return [] }
        return GitRefFilter.apply(query, to: refs)
    }

    func refs(in kind: GitRefKind) -> [GitRef] {
        visibleRefs.filter { $0.kind == kind }
    }

    /// Flat activation order, so arrow keys walk actions then every section in
    /// the same order the list renders them.
    var orderedIDs: [String] {
        visibleActions.map(\.id) + GitRefKind.allCases.flatMap { refs(in: $0).map(\.id) }
    }

    var proposedBranchName: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canCreateProposedBranch: Bool {
        !proposedBranchName.isEmpty && !isRunningAction
    }

    func present() {
        isPresented = true
        stage = .selectingRef
        query = ""
        errorMessage = nil
        selectedID = nil
        load()
    }

    func dismiss() {
        isPresented = false
        loadTask?.cancel()
        loadTask = nil
        actionTask?.cancel()
        actionTask = nil
        isLoading = false
        isRunningAction = false
        query = ""
        errorMessage = nil
        selectedID = nil
        stage = .selectingRef
    }

    /// Escape steps back one stage first so a mis-picked action does not throw
    /// away the whole picker.
    func goBack() -> Bool {
        guard stage != .selectingRef else { return false }
        stage = .selectingRef
        query = ""
        errorMessage = nil
        resetSelection()
        return true
    }

    func updateQuery(_ newQuery: String) {
        query = newQuery
        guard !stage.isNaming else { return }
        if let selectedID, orderedIDs.contains(selectedID) { return }
        resetSelection()
    }

    func moveSelection(by offset: Int) {
        let ids = orderedIDs
        guard !ids.isEmpty else {
            selectedID = nil
            return
        }
        guard let current = selectedID, let index = ids.firstIndex(of: current) else {
            selectedID = offset >= 0 ? ids[0] : ids[ids.count - 1]
            return
        }
        let next = min(max(index + offset, 0), ids.count - 1)
        selectedID = ids[next]
    }

    func activateSelection() {
        if stage.isNaming {
            createProposedBranch()
            return
        }
        guard let selectedID else { return }
        if let action = GitBranchPickerAction(rawValue: selectedID) {
            begin(action)
            return
        }
        guard let ref = visibleRefs.first(where: { $0.id == selectedID }) else { return }
        activate(ref)
    }

    func begin(_ action: GitBranchPickerAction) {
        errorMessage = nil
        query = ""
        switch action {
        case .createBranch:
            stage = .namingBranch(base: nil)
            selectedID = nil
        case .createBranchFrom:
            stage = .selectingBase
            resetSelection()
        case .checkoutDetached:
            stage = .selectingDetachRef
            resetSelection()
        }
    }

    func activate(_ ref: GitRef) {
        switch stage {
        case .selectingRef:
            checkout(ref)
        case .selectingBase:
            stage = .namingBranch(base: ref.name)
            query = ""
            selectedID = nil
        case .selectingDetachRef:
            perform { service, path in
                try await service.checkoutDetached(ref.name, workspacePath: path)
            }
        case .namingBranch:
            return
        }
    }

    func createProposedBranch() {
        guard canCreateProposedBranch, case .namingBranch(let base) = stage else { return }
        let name = proposedBranchName
        perform { service, path in
            try await service.createBranch(name, from: base, workspacePath: path)
        }
    }

    private func checkout(_ ref: GitRef) {
        guard !ref.isCurrent || ref.kind != .localBranch else { return }
        switch ref.kind {
        case .localBranch:
            perform { service, path in
                try await service.switchBranch(ref.name, workspacePath: path)
            }
        case .tag:
            perform { service, path in
                try await service.checkoutDetached(ref.name, workspacePath: path)
            }
        case .remoteBranch:
            let localName = ref.localTrackingName
            // A local branch of that name already exists, so plain checkout
            // picks it up instead of failing on a duplicate branch name.
            let hasLocal = refs.contains { $0.kind == .localBranch && $0.name == localName }
            perform { service, path in
                if hasLocal {
                    try await service.switchBranch(localName, workspacePath: path)
                } else {
                    try await service.checkoutTracking(
                        ref.name,
                        as: localName,
                        workspacePath: path
                    )
                }
            }
        }
    }

    private func load() {
        loadTask?.cancel()
        let requestID = UUID()
        loadID = requestID
        isLoading = true
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let loaded = try await service.refs(workspacePath: workspacePath)
                guard !Task.isCancelled, loadID == requestID else { return }
                refs = loaded
                isLoading = false
                if selectedID == nil { resetSelection() }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, loadID == requestID else { return }
                isLoading = false
                errorMessage = error.localizedDescription
                AppLogger.git.error(
                    "Git ref listing failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    /// Keeps the picker open on failure so the name or ref can be corrected,
    /// and closes it only once git actually changed HEAD.
    private func perform(
        operation: @escaping (GitService, String) async throws -> Void
    ) {
        guard !isRunningAction else { return }
        actionTask?.cancel()
        isRunningAction = true
        errorMessage = nil
        actionTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await operation(service, workspacePath)
                guard !Task.isCancelled else { return }
                isRunningAction = false
                actionTask = nil
                onRefChanged()
                dismiss()
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                isRunningAction = false
                actionTask = nil
                errorMessage = error.localizedDescription
                AppLogger.git.error(
                    "Git ref action failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    private func resetSelection() {
        selectedID = orderedIDs.first
    }
}
