import SwiftUI
import Observation

nonisolated struct DiffSelection: Equatable, Sendable {
    let change: GitChange
    let staged: Bool

    var displayName: String {
        URL(fileURLWithPath: change.path).lastPathComponent
    }

    var stateLabel: String {
        staged ? "Staged" : "Working Tree"
    }
}

@MainActor
@Observable
final class GitWorkspaceModel {
    private(set) var snapshot = GitSnapshot(
        status: GitStatus(changes: []),
        branch: "",
        branches: []
    )
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    let workspacePath: String
    private let service = GitService()
    private let onRepositoryChange: () -> Void
    private var refreshTask: Task<Void, Never>?
    private var actionTask: Task<Void, Never>?
    private var refreshID = UUID()

    init(
        workspacePath: String,
        onRepositoryChange: @escaping () -> Void = {}
    ) {
        self.workspacePath = workspacePath
        self.onRepositoryChange = onRepositoryChange
    }

    func refresh() {
        refreshTask?.cancel()
        let requestID = UUID()
        refreshID = requestID
        isLoading = true
        refreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await service.snapshot(workspacePath: workspacePath)
                guard !Task.isCancelled, refreshID == requestID else { return }
                if snapshot != result {
                    snapshot = result
                }
                errorMessage = nil
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, refreshID == requestID else { return }
                errorMessage = error.localizedDescription
                AppLogger.git.error("Git refresh failed: \(error.localizedDescription, privacy: .public)")
            }
            if refreshID == requestID {
                isLoading = false
            }
        }
    }

    func invalidate() {
        onRepositoryChange()
        refresh()
    }

    func stop() {
        refreshTask?.cancel()
        actionTask?.cancel()
    }

    func stage(_ change: GitChange) {
        perform { service, path in
            try await service.stage(path: change.path, workspacePath: path)
        }
    }

    func unstage(_ change: GitChange) {
        perform { service, path in
            try await service.unstage(
                path: change.path,
                originalPath: change.originalPath,
                workspacePath: path
            )
        }
    }

    func discard(_ change: GitChange) {
        perform { service, path in
            try await service.discard(path: change.path, workspacePath: path)
        }
    }

    func commit(message: String, onSuccess: @escaping () -> Void) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        perform(onSuccess: onSuccess) { service, path in
            try await service.commit(message: trimmed, workspacePath: path)
        }
    }

    func switchBranch(_ branch: String) {
        guard snapshot.branches.contains(branch) else { return }
        perform { service, path in
            try await service.switchBranch(branch, workspacePath: path)
        }
    }

    private func perform(
        onSuccess: @escaping () -> Void = {},
        operation: @escaping (GitService, String) async throws -> Void
    ) {
        actionTask?.cancel()
        actionTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await operation(service, workspacePath)
                guard !Task.isCancelled else { return }
                errorMessage = nil
                onRepositoryChange()
                onSuccess()
                refresh()
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
                AppLogger.git.error("Git action failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

struct ChangesView: View {
    let model: GitWorkspaceModel
    let onOpenDiff: (DiffSelection) -> Void
    @Environment(AtelierZoomModel.self) private var zoom
    @State private var commitMessage = ""
    @State private var discardCandidate: GitChange?
    @FocusState private var isCommitFieldFocused: Bool

    var body: some View {
        sourceControlPanel
            .background(AtelierTheme.sidebar)
            .confirmationDialog(
                "Discard changes to \(discardCandidate?.path ?? "this file")?",
                isPresented: Binding(
                    get: { discardCandidate != nil },
                    set: { if !$0 { discardCandidate = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Discard Changes", role: .destructive) {
                    if let change = discardCandidate { model.discard(change) }
                    discardCandidate = nil
                }
                Button("Cancel", role: .cancel) { discardCandidate = nil }
            } message: {
                Text("This restores the file from Git. This action cannot be undone in Atelier.")
            }
    }

    private var sourceControlPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            sourceControlHeader
                .atelierGitErrorEffect(value: model.errorMessage)
            repositoryHeader
            commitInput
            commitButton

            if let message = model.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .atelierFont(size: AtelierTypography.label)
                    .foregroundStyle(AtelierTheme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(AtelierMetrics.spaceM)
                    .environment(\.atelierZoomScale, zoom.sidebarScale)
            }

            if model.snapshot.status.changes.isEmpty {
                AtelierEmptyState(
                    systemImage: "checkmark.circle",
                    title: "Working tree clean",
                    message: "No staged or unstaged changes."
                )
                .environment(\.atelierZoomScale, zoom.sidebarScale)
            } else {
                List {
                    changeSection("Staged Changes", changes: model.snapshot.status.staged, staged: true)
                    changeSection("Changes", changes: model.snapshot.status.unstaged, staged: false)
                    changeSection("Untracked", changes: model.snapshot.status.untracked, staged: false)
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .background(AtelierTheme.sidebar)
                .atelierListChrome()
                .environment(\.atelierZoomScale, zoom.sidebarScale)
            }
        }
        .background(AtelierTheme.sidebar)
    }

    private var sourceControlHeader: some View {
        AtelierPanelHeader(title: "Source Control") {
            Button {
                model.refresh()
            } label: {
                if model.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(AtelierLuminareIconButtonStyle())
            .atelierRefreshCompletionEffect(isLoading: model.isLoading)
            .accessibilityLabel("Refresh Git status")
            .help("Refresh Git status")
        }
        .environment(\.atelierZoomScale, zoom.sidebarScale)
    }

    private var repositoryHeader: some View {
        HStack(spacing: AtelierMetrics.spaceS) {
            Image(systemName: "externaldrive")
                .foregroundStyle(.secondary)
            Text(repositoryName)
                .atelierFont(size: AtelierTypography.uiSize, weight: .medium)
                .lineLimit(1)
            Spacer(minLength: AtelierMetrics.spaceXS)
            BranchControl(
                current: model.snapshot.branch,
                branches: model.snapshot.branches,
                onSwitch: model.switchBranch
            )
        }
        .atelierFont(size: AtelierTypography.uiSize)
        .padding(.horizontal, AtelierMetrics.spaceM)
        .frame(height: AtelierMetrics.fieldHeight)
        .environment(\.atelierZoomScale, zoom.sidebarScale)
    }

    private var commitInput: some View {
        TextField(commitPlaceholder, text: $commitMessage)
            .textFieldStyle(.plain)
            .atelierFont(size: AtelierTypography.uiSize)
            .focused($isCommitFieldFocused)
            .padding(.horizontal, AtelierMetrics.spaceS)
            .frame(height: AtelierMetrics.fieldHeight)
            .atelierField(isFocused: isCommitFieldFocused)
            .padding(.horizontal, AtelierMetrics.spaceM)
            .onSubmit(commit)
            .environment(\.atelierZoomScale, zoom.sidebarScale)
    }

    private var commitButton: some View {
        Button("Commit", action: commit)
            .buttonStyle(AtelierFilledButtonStyle())
            .disabled(!canCommit)
            .padding(.horizontal, AtelierMetrics.spaceM)
            .padding(.top, AtelierMetrics.spaceS)
            .padding(.bottom, AtelierMetrics.spaceS)
            .environment(\.atelierZoomScale, zoom.sidebarScale)
    }

    @ViewBuilder
    private func changeSection(_ title: String, changes: [GitChange], staged: Bool) -> some View {
        if !changes.isEmpty {
            Section {
                ForEach(changes) { change in
                    GitChangeRow(
                        change: change,
                        staged: staged,
                        onOpen: {
                            onOpenDiff(DiffSelection(change: change, staged: staged))
                        },
                        onStage: { model.stage(change) },
                        onUnstage: { model.unstage(change) },
                        onDiscard: { discardCandidate = change }
                    )
                    .listRowInsets(
                        EdgeInsets(
                            top: 0,
                            leading: AtelierMetrics.spaceS,
                            bottom: 0,
                            trailing: AtelierMetrics.spaceS
                        )
                    )
                }
            } header: {
                Text(title.uppercased())
                    .atelierFont(size: AtelierTypography.caption, weight: .semibold)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var repositoryName: String {
        URL(fileURLWithPath: model.workspacePath).lastPathComponent
    }

    private var commitPlaceholder: String {
        let branch = model.snapshot.branch.isEmpty ? "HEAD" : model.snapshot.branch
        return "Message (⌘Enter to commit on \"\(branch)\")"
    }

    private var canCommit: Bool {
        !commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.snapshot.status.staged.isEmpty
    }

    private func commit() {
        model.commit(message: commitMessage) {
            commitMessage = ""
        }
    }
}

private struct GitChangeRow: View {
    let change: GitChange
    let staged: Bool
    let onOpen: () -> Void
    let onStage: () -> Void
    let onUnstage: () -> Void
    let onDiscard: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: AtelierMetrics.spaceS) {
            Button(action: onOpen) {
                HStack(spacing: AtelierMetrics.spaceS) {
                    Text(change.path)
                        .atelierFont(size: AtelierTypography.uiSize)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .atelierPointerCursor()

            HStack(spacing: AtelierMetrics.spaceXS) {
                Text(statusLabel)
                    .atelierFont(size: AtelierTypography.uiSize, weight: .medium)
                    .foregroundStyle(statusColor)
                    .frame(width: AtelierMetrics.spaceL)

                actionButtons
                    .opacity(isHovering ? 1 : AtelierTheme.inactiveOpacity)
            }
            .frame(width: actionWidth + AtelierMetrics.spaceL, alignment: .trailing)
        }
        .padding(.horizontal, AtelierMetrics.spaceXS)
        .frame(height: AtelierMetrics.rowHeight)
        .background {
            RoundedRectangle(cornerRadius: AtelierTheme.rowRadius, style: .continuous)
                .fill(isHovering ? AtelierTheme.hoverFill : Color.clear)
        }
        .onHover { hovering in
            guard isHovering != hovering else { return }
            isHovering = hovering
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: AtelierMetrics.spaceXS) {
            if staged {
                actionButton(
                    systemImage: "minus",
                    label: "Unstage \(change.path)",
                    help: "Unstage",
                    action: onUnstage
                )
            } else {
                actionButton(
                    systemImage: "plus",
                    label: "Stage \(change.path)",
                    help: "Stage",
                    action: onStage
                )
                if change.kind != .untracked {
                    actionButton(
                        systemImage: "arrow.uturn.backward",
                        label: "Discard changes to \(change.path)",
                        help: "Discard changes",
                        action: onDiscard
                    )
                }
            }
        }
    }

    private func actionButton(
        systemImage: String,
        label: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
        }
        .buttonStyle(AtelierRowIconButtonStyle())
        .accessibilityLabel(label)
        .help(help)
    }

    private var actionWidth: CGFloat {
        staged || change.kind == .untracked
            ? AtelierMetrics.compactControlHeight
            : AtelierMetrics.compactControlHeight * 2 + AtelierMetrics.spaceXS
    }

    private var statusColor: Color {
        switch change.kind {
        case .added: AtelierTheme.gitAdded
        case .untracked: AtelierTheme.gitUntracked
        case .deleted, .conflicted: AtelierTheme.gitDeleted
        case .renamed, .copied, .modified, .other: AtelierTheme.gitOrange
        }
    }

    private var statusLabel: String {
        switch change.kind {
        case .modified: "M"
        case .added: "A"
        case .deleted: "D"
        case .renamed: "R"
        case .copied: "C"
        case .untracked: "U"
        case .conflicted: "!"
        case .other: "?"
        }
    }
}
