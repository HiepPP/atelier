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

nonisolated enum GitCommitPolicy {
    private static let maximumChangedFiles = 100

    static func canPush(status: GitStatus) -> Bool {
        !status.changes.isEmpty
    }

    static func shouldStageAll(status: GitStatus) -> Bool {
        status.staged.isEmpty && !status.changes.isEmpty
    }

    static func generationRequest(paths: [String]) -> OllamaChatRequest {
        let uniquePaths = Array(Set(paths)).sorted()
        let includedPaths = uniquePaths.prefix(maximumChangedFiles)
        var lines = includedPaths.map { "- \($0)" }
        if uniquePaths.count > maximumChangedFiles {
            lines.append("- and \(uniquePaths.count - maximumChangedFiles) more changed files")
        }
        return OllamaChatRequest(
            messages: [
                OllamaChatMessage(
                    role: .system,
                    content: """
                    Write one concise Conventional Commit subject from changed file paths. \
                    Infer the most likely intent. Return exactly one plain-text line with no quotes, \
                    bullets, explanation, or Markdown. Keep it under 72 characters.
                    """
                ),
                OllamaChatMessage(
                    role: .user,
                    content: "Changed file paths:\n\(lines.joined(separator: "\n"))"
                )
            ],
            tools: []
        )
    }

    static func normalizedGeneratedMessage(_ response: String) -> String? {
        let lines = response.split(whereSeparator: \.isNewline)
        guard let first = lines.first(where: { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && trimmed != "```"
        }) else { return nil }
        let message = first.trimmingCharacters(
            in: CharacterSet.whitespacesAndNewlines.union(
                CharacterSet(charactersIn: "`\"'")
            )
        )
        return message.isEmpty ? nil : message
    }
}

nonisolated enum GitPushPhase: Equatable {
    case idle
    case generatingMessage
    case staging
    case committing
    case pushing

    var label: String {
        switch self {
        case .idle: "Push"
        case .generatingMessage: "Generating..."
        case .staging: "Staging..."
        case .committing: "Committing..."
        case .pushing: "Pushing..."
        }
    }
}

nonisolated enum GitCommitMessageError: LocalizedError, Equatable, Sendable {
    case timedOut

    var errorDescription: String? {
        "Ollama took too long to generate a commit message. Try again."
    }
}

actor GitCommitMessageGenerator {
    private let client: any OllamaChatStreaming
    private let timeout: Duration

    init(
        client: any OllamaChatStreaming = OllamaCloudClient(),
        timeout: Duration = .seconds(30)
    ) {
        self.client = client
        self.timeout = timeout
    }

    func generate(paths: [String]) async throws -> String {
        let request = GitCommitPolicy.generationRequest(paths: paths)
        let client = client
        do {
            return try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    let stream = await client.stream(request: request)
                    var response = ""
                    for try await chunk in stream {
                        if let content = chunk.message?.content {
                            response.append(content)
                        }
                    }
                    guard let message = GitCommitPolicy.normalizedGeneratedMessage(response) else {
                        throw GemmaAgentRuntimeError.emptyResponse
                    }
                    return message
                }
                group.addTask { [timeout] in
                    try await Task.sleep(for: timeout)
                    throw GitCommitMessageError.timedOut
                }
                guard let message = try await group.next() else {
                    throw GemmaAgentRuntimeError.emptyResponse
                }
                group.cancelAll()
                return message
            }
        } catch GitCommitMessageError.timedOut {
            await client.cancel()
            throw GitCommitMessageError.timedOut
        }
    }

    func cancel() async {
        await client.cancel()
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
    private(set) var isGeneratingCommitMessage = false
    private(set) var commitMessageGenerationError: String?
    private(set) var pushPhase = GitPushPhase.idle
    private(set) var recentCommits: [GitCommit] = []

    let workspacePath: String
    private let service = GitService()
    private let commitMessageGenerator: GitCommitMessageGenerator
    private let onRepositoryChange: () -> Void
    private var refreshTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?
    private var actionTask: Task<Void, Never>?
    private var invalidateTask: Task<Void, Never>?
    private var commitMessageTask: Task<Void, Never>?
    private var refreshID = UUID()
    private var statusRefreshID = UUID()
    private var pendingRepositoryMetadataRefresh = false

    init(
        workspacePath: String,
        onRepositoryChange: @escaping () -> Void = {},
        commitMessageClient: any OllamaChatStreaming = OllamaCloudClient()
    ) {
        self.workspacePath = workspacePath
        self.onRepositoryChange = onRepositoryChange
        commitMessageGenerator = GitCommitMessageGenerator(client: commitMessageClient)
    }

    var canGenerateCommitMessage: Bool {
        !snapshot.status.changes.isEmpty
            && !isGeneratingCommitMessage
            && pushPhase == .idle
    }

    var canPush: Bool {
        GitCommitPolicy.canPush(status: snapshot.status)
            && !isGeneratingCommitMessage
            && pushPhase == .idle
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
                isLoading = false

                do {
                    let commits = try await service.recentCommits(workspacePath: workspacePath)
                    guard !Task.isCancelled, refreshID == requestID else { return }
                    if recentCommits != commits {
                        recentCommits = commits
                    }
                } catch is CancellationError {
                    return
                } catch {
                    AppLogger.git.warning(
                        "Recent Git history refresh failed: \(error.localizedDescription, privacy: .public)"
                    )
                }
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

    /// Refresh only the working-tree status, keeping the current branch and
    /// branch list. Filesystem bursts use this so an edit spawns one `git
    /// status` instead of the full three-subprocess snapshot. No `isLoading`
    /// flag: a background status update must not flash the spinner on save.
    func refreshStatus() {
        statusTask?.cancel()
        let requestID = UUID()
        statusRefreshID = requestID
        statusTask = Task { [weak self] in
            guard let self else { return }
            do {
                let status = try await service.status(workspacePath: workspacePath)
                guard !Task.isCancelled, statusRefreshID == requestID else { return }
                if snapshot.status != status {
                    snapshot = GitSnapshot(
                        status: status,
                        branch: snapshot.branch,
                        branches: snapshot.branches
                    )
                }
                errorMessage = nil
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, statusRefreshID == requestID else { return }
                errorMessage = error.localizedDescription
                AppLogger.git.error("Git status refresh failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Filesystem-driven invalidations arrive in bursts; debounce the git
    /// subprocess refresh. Repository metadata changes require a full snapshot
    /// so branch and ref state cannot remain stale.
    func invalidate(repositoryMetadataChanged: Bool = false) {
        onRepositoryChange()
        pendingRepositoryMetadataRefresh = pendingRepositoryMetadataRefresh
            || repositoryMetadataChanged
        invalidateTask?.cancel()
        invalidateTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled else { return }
            let refreshRepositoryMetadata = pendingRepositoryMetadataRefresh
            pendingRepositoryMetadataRefresh = false
            if refreshRepositoryMetadata {
                refresh()
            } else {
                refreshStatus()
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        statusTask?.cancel()
        actionTask?.cancel()
        invalidateTask?.cancel()
        invalidateTask = nil
        pendingRepositoryMetadataRefresh = false
        cancelCommitMessageGeneration()
        pushPhase = .idle
    }

    func generateCommitMessage(onSuccess: @escaping (String) -> Void) {
        guard canGenerateCommitMessage else { return }
        let paths = snapshot.status.changes.map(\.path)
        isGeneratingCommitMessage = true
        commitMessageGenerationError = nil
        let generator = commitMessageGenerator
        commitMessageTask = Task { [weak self] in
            do {
                let message = try await generator.generate(paths: paths)
                guard let self, !Task.isCancelled else { return }
                isGeneratingCommitMessage = false
                commitMessageTask = nil
                onSuccess(message)
            } catch is CancellationError {
                return
            } catch let error as OllamaCloudError where error == .cancelled {
                return
            } catch {
                guard let self, !Task.isCancelled else { return }
                isGeneratingCommitMessage = false
                commitMessageTask = nil
                commitMessageGenerationError = error.localizedDescription
                AppLogger.git.error(
                    "Commit message generation failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    func cancelCommitMessageGeneration() {
        commitMessageTask?.cancel()
        commitMessageTask = nil
        isGeneratingCommitMessage = false
        let generator = commitMessageGenerator
        Task { await generator.cancel() }
    }

    func stage(_ change: GitChange) {
        perform { service, path in
            try await service.stage(path: change.path, workspacePath: path)
        }
    }

    func stageAll() {
        perform { service, path in
            try await service.stageAll(workspacePath: path)
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

    func push(
        onGeneratedMessage: @escaping (String) -> Void,
        onSuccess: @escaping () -> Void
    ) {
        guard canPush else { return }
        let paths = snapshot.status.changes.map(\.path)
        let shouldStageAll = GitCommitPolicy.shouldStageAll(status: snapshot.status)
        let generator = commitMessageGenerator
        actionTask?.cancel()
        pushPhase = .generatingMessage
        isGeneratingCommitMessage = true
        commitMessageGenerationError = nil
        errorMessage = nil
        actionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let message = try await generator.generate(paths: paths)
                try Task.checkCancellation()
                isGeneratingCommitMessage = false
                onGeneratedMessage(message)
                if shouldStageAll {
                    pushPhase = .staging
                    try await service.stageAll(workspacePath: workspacePath)
                }
                try Task.checkCancellation()
                pushPhase = .committing
                try await service.commit(message: message, workspacePath: workspacePath)
                try Task.checkCancellation()
                pushPhase = .pushing
                try await service.push(workspacePath: workspacePath)
                try Task.checkCancellation()
                pushPhase = .idle
                actionTask = nil
                onRepositoryChange()
                onSuccess()
                refresh()
            } catch is CancellationError {
                isGeneratingCommitMessage = false
                pushPhase = .idle
                actionTask = nil
            } catch let error as OllamaCloudError where error == .cancelled {
                isGeneratingCommitMessage = false
                pushPhase = .idle
                actionTask = nil
            } catch {
                let failedDuringGeneration = pushPhase == .generatingMessage
                isGeneratingCommitMessage = false
                pushPhase = .idle
                actionTask = nil
                if failedDuringGeneration {
                    commitMessageGenerationError = error.localizedDescription
                    AppLogger.git.error(
                        "Commit message generation failed: \(error.localizedDescription, privacy: .public)"
                    )
                } else {
                    errorMessage = error.localizedDescription
                    AppLogger.git.error(
                        "Git push pipeline failed: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
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

private enum SourceControlGroup: CaseIterable, Identifiable {
    case staged
    case changes

    var id: Self { self }

    var title: String {
        switch self {
        case .staged: "Staged"
        case .changes: "Changes"
        }
    }
}

struct ChangesView: View {
    let model: GitWorkspaceModel
    let onOpenDiff: (DiffSelection) -> Void
    var onClose: (() -> Void)? = nil
    var showsPanelHeader = true

    @Environment(AtelierZoomModel.self) private var zoom
    @State private var commitMessage = ""
    @State private var discardCandidate: GitChange?
    @State private var showsAllRecentCommits = false
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
            if showsPanelHeader {
                sourceControlHeader
                    .atelierGitErrorEffect(value: model.errorMessage)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: AtelierMetrics.spaceM) {
                    repositoryHeader

                    if let message = model.errorMessage {
                        errorBanner(message)
                    }

                    if model.isLoading, model.snapshot.branch.isEmpty {
                        loadingCard
                    } else {
                        commitInput
                        pushButton
                        changeList
                        recentCommitsSection
                    }
                }
                .padding(AtelierMetrics.spaceM)
                .padding(.bottom, AtelierMetrics.spaceL)
                .environment(\.atelierZoomScale, zoom.sidebarScale)
            }
            .scrollContentBackground(.hidden)
            .atelierScrollChrome(backgroundColor: AppKitThemeAdapter.sidebar)
            .background(AtelierTheme.sidebar)
        }
        .background(AtelierTheme.sidebar)
    }

    private var sourceControlHeader: some View {
        AtelierPanelHeader(title: "Source Control") {
            HStack(spacing: AtelierMetrics.spaceXS) {
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

                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(AtelierLuminareIconButtonStyle())
                    .accessibilityLabel("Close Source Control")
                    .help("Close Source Control")
                }
            }
        }
        .environment(\.atelierZoomScale, zoom.sidebarScale)
    }

    private var repositoryHeader: some View {
        HStack(spacing: AtelierMetrics.spaceM) {
            Text(repositoryInitial)
                .atelierFont(size: AtelierTypography.title, weight: .medium)
                .frame(width: 38, height: 38)
                .background(AtelierTheme.raised)
                .clipShape(RoundedRectangle(cornerRadius: AtelierTheme.controlRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: AtelierTheme.controlRadius)
                        .stroke(AtelierTheme.border, lineWidth: AtelierTheme.strokeControl)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(repositoryName)
                    .atelierFont(size: AtelierTypography.uiSize, weight: .semibold)
                    .lineLimit(1)
                Text(repositorySubtitle)
                    .atelierFont(size: AtelierTypography.micro, design: .monospaced)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Menu {
                if model.snapshot.branches.isEmpty {
                    Text("No local branches")
                } else {
                    Section("Switch branch") {
                        ForEach(model.snapshot.branches, id: \.self) { branch in
                            Button {
                                model.switchBranch(branch)
                            } label: {
                                if branch == model.snapshot.branch {
                                    Label(branch, systemImage: "checkmark")
                                } else {
                                    Text(branch)
                                }
                            }
                            .disabled(branch == model.snapshot.branch)
                        }
                    }
                }

                Divider()
                Button("Refresh Repository", systemImage: "arrow.clockwise") {
                    model.refresh()
                }
            } label: {
                Image(systemName: "chevron.down")
                    .atelierFont(size: AtelierTypography.micro, weight: .semibold)
                    .foregroundStyle(.secondary)
                    .frame(
                        width: AtelierMetrics.compactControlHeight,
                        height: AtelierMetrics.compactControlHeight
                    )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .atelierPointerCursor()
            .accessibilityLabel("Switch branch")
            .help("Switch branch")
        }
        .padding(AtelierMetrics.spaceM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .atelierCard(fill: AtelierTheme.raised.opacity(0.48))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Repository \(repositoryName), branch \(currentBranch)")
    }

    private var commitInput: some View {
        VStack(alignment: .leading, spacing: AtelierMetrics.spaceXS) {
            Text("Commit message")
                .atelierFont(size: AtelierTypography.caption, weight: .semibold)
                .foregroundStyle(.secondary)

            ZStack(alignment: .topLeading) {
                if commitMessage.isEmpty {
                    Text("Write a commit message...")
                        .atelierFont(size: AtelierTypography.uiSize)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, AtelierMetrics.spaceS + 2)
                        .padding(.top, AtelierMetrics.spaceS + 1)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $commitMessage)
                    .scrollContentBackground(.hidden)
                    .atelierScrollChrome(backgroundColor: AppKitThemeAdapter.editor)
                    .atelierFont(size: AtelierTypography.uiSize)
                    .focused($isCommitFieldFocused)
                    .padding(AtelierMetrics.spaceXS)
                    .frame(minHeight: 76, maxHeight: 92)
            }
            .atelierField(isFocused: isCommitFieldFocused)

            if let message = model.commitMessageGenerationError {
                Text(message)
                    .atelierFont(size: AtelierTypography.micro)
                    .foregroundStyle(AtelierTheme.danger)
                    .accessibilityLabel("Gemma error: \(message)")
            }
        }
        .padding(.horizontal, AtelierMetrics.spaceS)
        .padding(.vertical, AtelierMetrics.spaceS)
        .atelierCard(fill: AtelierTheme.panel.opacity(0.72))
    }

    private var pushButton: some View {
        Button(action: push) {
            HStack(spacing: AtelierMetrics.spaceS) {
                if model.pushPhase == .idle {
                    Image(systemName: "arrow.up")
                } else {
                    ProgressView().controlSize(.small)
                }
                Text(pushLabel)
            }
            .atelierFont(size: AtelierTypography.uiSize, weight: .semibold)
            .foregroundStyle(model.canPush ? AtelierTheme.accentInk : Color.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(model.canPush ? AtelierTheme.accent : AtelierTheme.raised)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!model.canPush)
        .keyboardShortcut(.return, modifiers: .command)
        .atelierPointerCursor()
        .clipShape(RoundedRectangle(cornerRadius: AtelierTheme.controlRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AtelierTheme.controlRadius, style: .continuous)
                .stroke(AtelierTheme.border, lineWidth: AtelierTheme.strokeControl)
        }
        .accessibilityLabel("Generate commit message, commit changes, and push \(currentBranch)")
        .accessibilityValue(model.pushPhase.label)
        .help("Generate a Gemma message, commit changes, and push \(currentBranch)")
    }

    private var changeList: some View {
        LazyVStack(alignment: .leading, spacing: AtelierMetrics.spaceM) {
            ForEach(SourceControlGroup.allCases) { group in
                changeGroup(group)
            }
        }
    }

    private func changeGroup(_ group: SourceControlGroup) -> some View {
        let changes = changes(for: group)

        return VStack(alignment: .leading, spacing: AtelierMetrics.spaceS) {
            HStack(spacing: AtelierMetrics.spaceXS) {
                Text(group.title)
                    .atelierFont(size: AtelierTypography.headline, weight: .semibold)

                Text("\(changes.count)")
                    .atelierFont(size: AtelierTypography.micro, design: .monospaced)
                    .foregroundStyle(.secondary)
            }

            if changes.isEmpty {
                HStack(spacing: AtelierMetrics.spaceS) {
                    Image(systemName: group == .staged ? "tray" : "checkmark.circle")
                        .foregroundStyle(.secondary)
                    Text(group == .staged ? "No staged changes." : "Working tree clean.")
                        .atelierFont(size: AtelierTypography.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AtelierMetrics.spaceM)
                .atelierCard(fill: AtelierTheme.raised.opacity(0.30))
            } else {
                LazyVStack(spacing: AtelierMetrics.spaceXS) {
                    ForEach(changes) { change in
                        GitChangeRow(
                            change: change,
                            staged: group == .staged,
                            onOpen: {
                                onOpenDiff(
                                    DiffSelection(
                                        change: change,
                                        staged: group == .staged
                                    )
                                )
                            },
                            onStage: { model.stage(change) },
                            onUnstage: { model.unstage(change) },
                            onDiscard: { discardCandidate = change }
                        )
                        .padding(.horizontal, AtelierMetrics.spaceXS)
                        .atelierCard(fill: AtelierTheme.raised.opacity(0.30))
                    }
                }
            }
        }
    }

    private var recentCommitsSection: some View {
        VStack(alignment: .leading, spacing: AtelierMetrics.spaceS) {
            HStack {
                Text("Recent commits")
                    .atelierFont(size: AtelierTypography.headline, weight: .semibold)

                Spacer(minLength: 0)

                if model.recentCommits.count > 3 {
                    Button(showsAllRecentCommits ? "Show less" : "View all") {
                        showsAllRecentCommits.toggle()
                    }
                    .buttonStyle(AtelierGhostButtonStyle(tint: AtelierTheme.gitOrange))
                }
            }

            if visibleRecentCommits.isEmpty {
                Text("No commits yet")
                    .atelierFont(size: AtelierTypography.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, AtelierMetrics.spaceS)
            } else {
                LazyVStack(spacing: AtelierMetrics.spaceXS) {
                    ForEach(visibleRecentCommits) { commit in
                        RecentCommitRow(
                            commit: commit,
                            isHead: commit.id == model.recentCommits.first?.id
                        )
                    }
                }
            }
        }
        .padding(.top, AtelierMetrics.spaceS)
    }

    private func errorBanner(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: AtelierMetrics.spaceS) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .atelierFont(size: AtelierTypography.label)
                .foregroundStyle(AtelierTheme.danger)
            Button("Try Again") { model.refresh() }
                .buttonStyle(AtelierGhostButtonStyle(tint: AtelierTheme.danger))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AtelierMetrics.spaceM)
        .atelierCard(fill: AtelierTheme.danger.opacity(0.06))
    }

    private var loadingCard: some View {
        HStack(spacing: AtelierMetrics.spaceS) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text("Checking repository")
                    .atelierFont(size: AtelierTypography.label, weight: .semibold)
                Text("Reading branch, changes, and recent commits.")
                    .atelierFont(size: AtelierTypography.micro)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(AtelierMetrics.spaceM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .atelierCard(fill: AtelierTheme.raised.opacity(0.35))
    }

    private func changes(for group: SourceControlGroup) -> [GitChange] {
        switch group {
        case .staged:
            model.snapshot.status.staged
        case .changes:
            model.snapshot.status.unstaged + model.snapshot.status.untracked
        }
    }

    private var visibleRecentCommits: [GitCommit] {
        Array(model.recentCommits.prefix(showsAllRecentCommits ? 10 : 3))
    }

    private var repositoryName: String {
        URL(fileURLWithPath: model.workspacePath).lastPathComponent
    }

    private var repositoryInitial: String {
        repositoryName.first.map { String($0).lowercased() } ?? "?"
    }

    private var repositorySubtitle: String {
        "\(shortenedWorkspacePath) - \(currentBranch)"
    }

    private var shortenedWorkspacePath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard model.workspacePath == home || model.workspacePath.hasPrefix(home + "/") else {
            return model.workspacePath
        }
        return "~" + model.workspacePath.dropFirst(home.count)
    }

    private var currentBranch: String {
        model.snapshot.branch.isEmpty ? "Detached HEAD" : model.snapshot.branch
    }

    private var pushLabel: String {
        model.pushPhase == .idle ? "Push \(currentBranch)" : model.pushPhase.label
    }

    private func push() {
        isCommitFieldFocused = false
        model.push(onGeneratedMessage: { message in
            commitMessage = message
        }) {
            commitMessage = ""
        }
    }
}

private struct RecentCommitRow: View {
    let commit: GitCommit
    let isHead: Bool

    var body: some View {
        HStack(alignment: .top, spacing: AtelierMetrics.spaceS) {
            AsyncImage(url: commit.authorAvatarURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .empty, .failure:
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.tertiary)
                @unknown default:
                    EmptyView()
                }
            }
                .frame(width: 30, height: 30)
                .clipShape(Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: AtelierMetrics.spaceXS) {
                    Text(commit.subject)
                        .atelierFont(size: AtelierTypography.label, weight: .medium)
                        .lineLimit(1)

                    if isHead {
                        Text("HEAD")
                            .atelierFont(size: AtelierTypography.micro, weight: .semibold)
                            .foregroundStyle(AtelierTheme.gitUntracked)
                            .padding(.horizontal, AtelierMetrics.spaceXS)
                            .padding(.vertical, 2)
                            .background(AtelierTheme.gitUntracked.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: AtelierTheme.rowRadius))
                    }
                }

                HStack(spacing: AtelierMetrics.spaceXS) {
                    Circle()
                        .fill(AtelierTheme.gitAdded)
                        .frame(width: 5, height: 5)
                    Text(commit.author)
                    Text("-")
                    Text(commit.date, style: .relative)
                }
                .atelierFont(size: AtelierTypography.micro)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(commit.shortHash)
                .atelierFont(size: AtelierTypography.micro, design: .monospaced)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.top, 1)
        }
        .padding(.vertical, AtelierMetrics.spaceS)
        .accessibilityElement(children: .combine)
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
            VStack(alignment: .leading, spacing: 1) {
                Text(URL(fileURLWithPath: change.path).lastPathComponent)
                    .atelierFont(size: AtelierTypography.label, weight: .medium)
                    .lineLimit(1)

                let parent = (change.path as NSString).deletingLastPathComponent
                if !parent.isEmpty {
                    Text(parent)
                        .atelierFont(size: AtelierTypography.micro, design: .monospaced)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onOpen() }

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
        .frame(minHeight: AtelierMetrics.rowHeight + AtelierMetrics.spaceS)
        .background {
            RoundedRectangle(cornerRadius: AtelierTheme.rowRadius, style: .continuous)
                .fill(isHovering ? AtelierTheme.hoverFill : Color.clear)
        }
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
        .atelierPointerCursor()
        .onHover { hovering in
            guard isHovering != hovering else { return }
            isHovering = hovering
        }
        .contextMenu {
            Button("Open Diff", action: onOpen)
            Divider()
            if staged {
                Button("Unstage", action: onUnstage)
            } else {
                Button("Stage", action: onStage)
                if change.kind != .untracked {
                    Button("Discard Changes...", role: .destructive, action: onDiscard)
                }
            }
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
