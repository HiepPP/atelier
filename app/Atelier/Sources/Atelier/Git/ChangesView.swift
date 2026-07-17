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
                snapshot = result
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
    @State private var hoveredChangeID: String?

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
                    .atelierFont(size: AtelierTypography.uiSize)
                    .foregroundStyle(AtelierTheme.gitDeleted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(11)
                    .environment(\.atelierZoomScale, zoom.sidebarScale)
            }

            if model.snapshot.status.changes.isEmpty {
                Spacer(minLength: 0)
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
        HStack(spacing: 10) {
            Text("SOURCE CONTROL")
                .atelierFont(size: AtelierTypography.uiSize)
            Spacer()
            Image(systemName: "ellipsis")
            Image(systemName: "arrow.up.left.and.arrow.down.right")
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .frame(height: 36)
        .environment(\.atelierZoomScale, zoom.sidebarScale)
    }

    private var repositoryHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.down")
                .atelierFont(size: 10, weight: .medium)
            Image(systemName: "desktopcomputer")
            Text(repositoryName)
                .atelierFont(size: AtelierTypography.uiSize, weight: .medium)
                .lineLimit(1)
            Spacer(minLength: 4)
            BranchControl(
                current: model.snapshot.branch,
                branches: model.snapshot.branches,
                onSwitch: model.switchBranch
            )
            Image(systemName: "arrow.triangle.2.circlepath")
                .help("Synchronize changes")
            Button(action: commit) {
                Image(systemName: "checkmark")
            }
            .buttonStyle(.plain)
            .disabled(!canCommit)
            Button {
                model.refresh()
            } label: {
                if model.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.plain)
            .atelierRefreshCompletionEffect(isLoading: model.isLoading)
            .help("Refresh git status")
            Image(systemName: "ellipsis")
        }
        .atelierFont(size: AtelierTypography.uiSize)
        .padding(.horizontal, 11)
        .frame(height: 32)
        .environment(\.atelierZoomScale, zoom.sidebarScale)
    }

    private var commitInput: some View {
        TextField(commitPlaceholder, text: $commitMessage)
            .textFieldStyle(.plain)
            .atelierFont(size: AtelierTypography.uiSize)
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(AtelierTheme.editor)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(AtelierTheme.border, lineWidth: 1)
            }
            .padding(.horizontal, 11)
            .onSubmit(commit)
            .environment(\.atelierZoomScale, zoom.sidebarScale)
    }

    private var commitButton: some View {
        HStack(spacing: 0) {
            Button(action: commit) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                    Text("Commit")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(AtelierTheme.editor.opacity(0.55))
                .frame(width: 1)

            Menu {
                Button("Commit", action: commit)
            } label: {
                Image(systemName: "chevron.down")
                    .frame(width: 30, height: 28)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
        }
        .atelierFont(size: AtelierTypography.uiSize)
        .foregroundStyle(AtelierTheme.editor)
        .frame(height: 29)
        .background(AtelierTheme.accent.opacity(canCommit ? 1 : 0.42))
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .disabled(!canCommit)
        .padding(.horizontal, 11)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .environment(\.atelierZoomScale, zoom.sidebarScale)
    }

    @ViewBuilder
    private func changeSection(_ title: String, changes: [GitChange], staged: Bool) -> some View {
        if !changes.isEmpty {
            Section {
                ForEach(changes) { change in
                    HStack(spacing: 8) {
                        Button {
                            onOpenDiff(DiffSelection(change: change, staged: staged))
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "doc")
                                    .foregroundStyle(color(for: change.kind))
                                Text(change.path)
                                    .atelierFont(size: AtelierTypography.uiSize)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .atelierPointerCursor()

                        if hoveredChangeID == change.id {
                            if staged {
                                Button {
                                    model.unstage(change)
                                } label: {
                                    Image(systemName: "minus")
                                }
                                .buttonStyle(.plain)
                                .help("Unstage")
                            } else {
                                Button {
                                    model.stage(change)
                                } label: {
                                    Image(systemName: "plus")
                                }
                                .buttonStyle(.plain)
                                .help("Stage")
                                if change.kind != .untracked {
                                    Button {
                                        discardCandidate = change
                                    } label: {
                                        Image(systemName: "arrow.uturn.backward")
                                    }
                                    .buttonStyle(.plain)
                                    .help("Discard changes")
                                }
                            }
                        } else {
                            Text(statusLabel(for: change.kind))
                                .atelierFont(size: AtelierTypography.uiSize, weight: .medium)
                                .foregroundStyle(color(for: change.kind))
                        }
                    }
                    .frame(height: 24)
                    .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 10))
                    .onHover { hoveredChangeID = $0 ? change.id : nil }
                }
            } header: {
                Text(title.uppercased())
                    .atelierFont(size: 11, weight: .semibold)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func color(for kind: GitChangeKind) -> Color {
        switch kind {
        case .added: AtelierTheme.gitAdded
        case .untracked: AtelierTheme.gitUntracked
        case .deleted, .conflicted: AtelierTheme.gitDeleted
        case .renamed, .copied, .modified, .other: AtelierTheme.gitOrange
        }
    }

    private func statusLabel(for kind: GitChangeKind) -> String {
        switch kind {
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
