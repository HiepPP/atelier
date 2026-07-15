import SwiftUI

struct DiffSelection: Equatable {
    let change: GitChange
    let staged: Bool
}

@MainActor
final class GitWorkspaceModel: ObservableObject {
    @Published private(set) var snapshot = GitSnapshot(
        status: GitStatus(changes: []),
        branch: "",
        branches: []
    )
    @Published private(set) var diffText = "Select a changed file to view its diff."
    @Published private(set) var selection: DiffSelection?
    @Published private(set) var diffNeedsReload = false
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    let workspacePath: String
    private let service = GitService()
    private var refreshTask: Task<Void, Never>?
    private var diffTask: Task<Void, Never>?
    private var actionTask: Task<Void, Never>?
    private var refreshID = UUID()

    init(workspacePath: String) {
        self.workspacePath = workspacePath
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
            }
            if refreshID == requestID { isLoading = false }
        }
    }

    func invalidate() {
        if selection != nil { diffNeedsReload = true }
        refresh()
    }

    func select(_ change: GitChange, staged: Bool) {
        selection = DiffSelection(change: change, staged: staged)
        loadSelectedDiff()
    }

    func loadSelectedDiff() {
        guard let selection else { return }
        diffTask?.cancel()
        diffNeedsReload = false
        if selection.change.kind == .untracked {
            diffText = "Untracked file. Stage it to view a unified diff."
            return
        }
        diffTask = Task { [weak self] in
            guard let self else { return }
            do {
                let output = try await service.diff(
                    path: selection.change.path,
                    originalPath: selection.change.originalPath,
                    staged: selection.staged,
                    workspacePath: workspacePath
                )
                guard !Task.isCancelled, self.selection == selection else { return }
                diffText = output
                errorMessage = nil
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, self.selection == selection else { return }
                diffText = "Could not load diff: \(error.localizedDescription)"
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        diffTask?.cancel()
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
                selection = nil
                diffText = "Select a changed file to view its diff."
                onSuccess()
                refresh()
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct ChangesView: View {
    @ObservedObject var model: GitWorkspaceModel
    @State private var commitMessage = ""
    @State private var discardCandidate: GitChange?

    var body: some View {
        VSplitView {
            VStack(alignment: .leading, spacing: 0) {
                gitActivityBar

                HStack {
                    BranchControl(
                        current: model.snapshot.branch,
                        branches: model.snapshot.branches,
                        onSwitch: model.switchBranch
                    )
                    Spacer()
                    if model.isLoading { ProgressView().controlSize(.small) }
                    Button {
                        model.refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(AtelierIconButtonStyle())
                    .help("Refresh git status")
                }
                .padding(.horizontal, 10)
                .frame(height: 36)
                .background(AtelierTheme.sidebar)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(AtelierTheme.border)
                        .frame(height: 0.5)
                }

                if let message = model.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.red)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08))
                }

                if model.snapshot.status.changes.isEmpty && !model.isLoading {
                    VStack(spacing: 10) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 32, weight: .ultraLight))
                            .foregroundStyle(AtelierTheme.accent)
                        Text("Working tree clean")
                            .font(.system(size: 15, weight: .semibold))
                        Text("No staged or unstaged files.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        changeSection("Staged", changes: model.snapshot.status.staged, staged: true)
                        changeSection("Unstaged", changes: model.snapshot.status.unstaged, staged: false)
                        changeSection("Untracked", changes: model.snapshot.status.untracked, staged: false)
                    }
                    .listStyle(.sidebar)
                    .scrollContentBackground(.hidden)
                    .background(AtelierTheme.sidebar)
                    .atelierListChrome()
                }

                HStack(spacing: 8) {
                    TextField("Commit message", text: $commitMessage)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(AtelierTheme.editor)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: AtelierTheme.controlRadius,
                                style: .continuous
                            )
                        )
                        .overlay {
                            RoundedRectangle(
                                cornerRadius: AtelierTheme.controlRadius,
                                style: .continuous
                            )
                            .stroke(AtelierTheme.border, lineWidth: 0.75)
                        }
                        .onSubmit(commit)
                    Button("Commit") { commit() }
                        .buttonStyle(AtelierPrimaryButtonStyle())
                        .disabled(
                            commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || model.snapshot.status.staged.isEmpty
                        )
                }
                .padding(8)
                .background(AtelierTheme.chrome)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(AtelierTheme.border)
                        .frame(height: 0.5)
                }
            }
            .frame(minHeight: 280, idealHeight: 430)
            .background(AtelierTheme.sidebar)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .foregroundStyle(AtelierTheme.accent)
                    Text(model.selection?.change.path ?? "No diff selected")
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    if model.diffNeedsReload {
                        Button {
                            model.loadSelectedDiff()
                        } label: {
                            Label("Reload", systemImage: "arrow.clockwise")
                                .padding(.horizontal, 7)
                        }
                        .buttonStyle(AtelierIconButtonStyle())
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 36)
                .background(AtelierTheme.chrome)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(AtelierTheme.border)
                        .frame(height: 0.5)
                }

                DiffView(text: model.diffText)
            }
            .frame(minHeight: 200, idealHeight: 280)
            .background(AtelierTheme.editor)
        }
        .atelierSplitViewChrome()
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

    @ViewBuilder
    private func changeSection(_ title: String, changes: [GitChange], staged: Bool) -> some View {
        if !changes.isEmpty {
            Section {
                ForEach(changes) { change in
                    HStack(spacing: 8) {
                        Button {
                            model.select(change, staged: staged)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: icon(for: change.kind))
                                    .foregroundStyle(color(for: change.kind))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(change.path)
                                        .font(.system(size: 11.5, weight: .medium))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Text(change.kind.rawValue)
                                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)

                        if staged {
                            Button {
                                model.unstage(change)
                            } label: {
                                Image(systemName: "minus")
                            }
                            .buttonStyle(AtelierIconButtonStyle())
                            .help("Unstage")
                        } else {
                            Button {
                                model.stage(change)
                            } label: {
                                Image(systemName: "plus")
                            }
                            .buttonStyle(AtelierIconButtonStyle())
                            .help("Stage")
                            if change.kind != .untracked {
                                Button {
                                    discardCandidate = change
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(AtelierIconButtonStyle())
                                .help("Discard changes")
                            }
                        }
                    }
                    .padding(.vertical, 3)
                }
            } header: {
                Text(title.uppercased())
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var gitActivityBar: some View {
        HStack(spacing: 2) {
            Image(systemName: "line.3.horizontal.decrease")
                .foregroundStyle(.primary)
                .frame(width: 32, height: 40)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(AtelierTheme.gitOrange)
                        .frame(height: 1.5)
                }

            HStack(spacing: 3) {
                Image(systemName: "arrow.triangle.branch")
                Text("\(model.snapshot.status.changes.count)")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(.secondary)
            .frame(height: 40)

            Spacer()
        }
        .padding(.horizontal, 4)
        .background(AtelierTheme.chrome)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AtelierTheme.border)
                .frame(height: 0.5)
        }
    }

    private func icon(for kind: GitChangeKind) -> String {
        switch kind {
        case .added, .untracked: "plus.circle"
        case .deleted: "minus.circle"
        case .renamed, .copied: "arrow.right.circle"
        case .conflicted: "exclamationmark.triangle"
        case .modified, .other: "pencil.circle"
        }
    }

    private func color(for kind: GitChangeKind) -> Color {
        switch kind {
        case .added, .untracked: .green
        case .deleted, .conflicted: .red
        case .renamed, .copied: .blue
        case .modified, .other: .orange
        }
    }

    private func commit() {
        model.commit(message: commitMessage) {
            commitMessage = ""
        }
    }
}
