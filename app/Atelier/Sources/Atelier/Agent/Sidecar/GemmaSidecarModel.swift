import Foundation
import Observation
import Synchronization

/// One-shot bridge between a background run's work task and the caller awaiting
/// its result. The caller parks on `attach`; `finish` resumes it with the work
/// result, and `abandon` unparks it with `CancellationError` even when the work
/// task never completes (a wedged request that ignores cancellation). Whichever
/// of `finish`/`abandon` arrives first wins; the loser is dropped.
nonisolated final class SidecarRunHandoff: Sendable {
    private enum State {
        case waiting
        case attached(CheckedContinuation<String, any Error>)
        case finished(Result<String, any Error>)
        case abandoned
    }

    private let state = Mutex<State>(.waiting)

    func attach(_ continuation: CheckedContinuation<String, any Error>) {
        let immediate: Result<String, any Error>? = state.withLock { current in
            switch current {
            case .waiting:
                current = .attached(continuation)
                return nil
            case .finished(let result):
                return result
            case .attached, .abandoned:
                return .failure(CancellationError())
            }
        }
        if let immediate { continuation.resume(with: immediate) }
    }

    func finish(_ result: Result<String, any Error>) {
        let attached: CheckedContinuation<String, any Error>? = state.withLock { current in
            switch current {
            case .waiting:
                current = .finished(result)
                return nil
            case .attached(let continuation):
                current = .finished(result)
                return continuation
            case .finished, .abandoned:
                return nil
            }
        }
        attached?.resume(with: result)
    }

    func abandon() {
        let attached: CheckedContinuation<String, any Error>? = state.withLock { current in
            switch current {
            case .waiting:
                current = .abandoned
                return nil
            case .attached(let continuation):
                current = .abandoned
                return continuation
            case .finished, .abandoned:
                return nil
            }
        }
        attached?.resume(throwing: CancellationError())
    }
}

/// Serializes background Gemma runs so at most one executes at a time. A new run
/// cancels any in-flight run before starting, and the runtime history is reset
/// before each run so background calls stay one-shot. Every wait here is
/// abandonable: preemption or `cancelAll` unparks the previous caller with
/// `CancellationError`, and a successor waiting for its cancelled predecessor to
/// unwind gives up as soon as the successor is itself cancelled, so one wedged
/// request can never park the sidecar features forever.
actor SidecarBackgroundRunner {
    private let runtime: GemmaAgentRuntime
    private var current: (work: Task<String, any Error>, handoff: SidecarRunHandoff)?

    init(runtime: GemmaAgentRuntime) {
        self.runtime = runtime
    }

    func run(prompt: String) async throws -> String {
        let previous = current
        previous?.work.cancel()
        previous?.handoff.abandon()
        await runtime.cancel()
        let runtime = self.runtime
        let work = Task<String, any Error> {
            if let previousWork = previous?.work {
                await Self.waitAbandoningOnCancellation(for: previousWork)
            }
            try Task.checkCancellation()
            await runtime.reset()
            var text = ""
            let events = await runtime.events(for: prompt)
            for try await event in events {
                try Task.checkCancellation()
                if case .assistantDelta(let delta) = event { text += delta }
            }
            return text
        }
        let handoff = SidecarRunHandoff()
        current = (work, handoff)
        Task { handoff.finish(await work.result) }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { handoff.attach($0) }
        } onCancel: {
            work.cancel()
            handoff.abandon()
        }
    }

    /// Waits until `task` finishes or the current task is cancelled, whichever
    /// comes first. A wedged `task` is abandoned, never awaited forever.
    private static func waitAbandoningOnCancellation(for task: Task<String, any Error>) async {
        let handoff = SidecarRunHandoff()
        Task { handoff.finish(await task.result) }
        _ = try? await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { handoff.attach($0) }
        } onCancel: {
            handoff.abandon()
        }
    }

    func cancelAll() async {
        current?.work.cancel()
        current?.handoff.abandon()
        await runtime.cancel()
    }
}

/// Best-effort reachability hint updated by background runs. Features must still
/// handle thrown transport errors from `runBackground`.
@MainActor
final class SidecarReachability {
    var value = true
}

/// Owns the Gemma sidecar's interactive response area, a separate serialized
/// background runtime, the shared read-only service surface, and the six
/// feature instances. Separate from `WorkspaceSession.gemmaAgent` (the chat tab).
///
/// This model and `GemmaSidecarView` must not require changes when a feature is
/// implemented. Feature builders edit only their own file under `Agent/Sidecar`.
@MainActor
@Observable
final class GemmaSidecarModel {
    private static let tickInterval: TimeInterval = 45

    let interactive: GemmaAgentModel
    let services: SidecarServices

    let terminalActions: SidecarTerminalActionsModel
    let guardian: TerminalGuardianModel
    let briefing: ClaudeBriefingModel
    let journal: SessionJournalModel
    let intentGuard: IntentGuardModel
    let whisper: PrecommitWhisperModel

    private let terminalTabs: TerminalTabsModel
    private let background: SidecarBackgroundRunner
    private let reachability: SidecarReachability
    private var timerTask: Task<Void, Never>?

    init(
        terminalTabs: TerminalTabsModel,
        gitModel: GitWorkspaceModel,
        workspaceRoot: URL,
        gitService: GitService = GitService(),
        interactiveClient: any OllamaChatStreaming = OllamaCloudClient(),
        backgroundClient: any OllamaChatStreaming = OllamaCloudClient()
    ) {
        let workspacePath = workspaceRoot.path
        let snapshot: (@MainActor @Sendable (Int) -> String?) = { [weak terminalTabs] lines in
            terminalTabs?.selectedTerminalScrollback(lines: lines)
        }
        let interactiveModel = GemmaAgentModel(
            runtime: GemmaAgentRuntime(
                client: interactiveClient,
                tools: WorkspaceToolExecutor(
                    workspaceRoot: workspaceRoot,
                    gitService: gitService,
                    terminalSnapshot: snapshot
                )
            )
        )
        let runner = SidecarBackgroundRunner(
            runtime: GemmaAgentRuntime(
                client: backgroundClient,
                tools: WorkspaceToolExecutor(
                    workspaceRoot: workspaceRoot,
                    gitService: gitService,
                    terminalSnapshot: snapshot
                )
            )
        )
        let reachability = SidecarReachability()

        let services = SidecarServices(
            currentContext: { [weak terminalTabs] in
                terminalTabs?.selectedSidecarContext
            },
            runBackground: { [runner, reachability] prompt in
                do {
                    let text = try await runner.run(prompt: prompt)
                    reachability.value = true
                    return text
                } catch {
                    if let cloud = error as? OllamaCloudError, case .connection = cloud {
                        reachability.value = false
                    }
                    throw error
                }
            },
            runInteractive: { [weak interactiveModel] prompt in
                interactiveModel?.send(prompt)
            },
            readTerminalOutput: { [weak terminalTabs] lines in
                terminalTabs?.selectedTerminalScrollback(lines: lines)
            },
            unstagedDiff: { [gitService, workspacePath] in
                let data = try? await gitService.run(
                    arguments: ["diff", "--no-color", "--no-ext-diff"],
                    workspacePath: workspacePath,
                    maxOutputBytes: 500_000
                )
                return data.map { String(decoding: $0, as: UTF8.self) } ?? ""
            },
            changedFiles: { [weak gitModel] in
                gitModel?.snapshot.status.changes.map(\.path) ?? []
            },
            diffStat: { [gitService, workspacePath] in
                let data = try? await gitService.run(
                    arguments: ["diff", "--stat", "--no-color"],
                    workspacePath: workspacePath,
                    maxOutputBytes: 100_000
                )
                return data.map { String(decoding: $0, as: UTF8.self) } ?? ""
            },
            pasteIntoTerminal: { [weak terminalTabs] text in
                terminalTabs?.pasteIntoSelectedTerminal(text) ?? false
            },
            isOllamaConfigured: { [reachability] in
                reachability.value
            }
        )

        self.terminalTabs = terminalTabs
        self.interactive = interactiveModel
        self.background = runner
        self.reachability = reachability
        self.services = services
        self.terminalActions = SidecarTerminalActionsModel(services: services)
        self.guardian = TerminalGuardianModel(services: services)
        self.briefing = ClaudeBriefingModel(services: services)
        self.journal = SessionJournalModel(services: services)
        self.intentGuard = IntentGuardModel(services: services)
        self.whisper = PrecommitWhisperModel(services: services)

        interactiveModel.contextProvider = { [weak terminalTabs] in
            GemmaSidecarContextComposer.contextBlock(for: terminalTabs?.selectedSidecarContext)
        }
    }

    /// Context derived from the selected center tab. Reads the observable tab
    /// model so views recompute on selection change.
    var context: GemmaSidecarTabContext? {
        terminalTabs.selectedSidecarContext
    }

    /// Built-in and feature quick actions for the given context.
    func allQuickActions(for context: GemmaSidecarTabContext?) -> [SidecarQuickAction] {
        guard let context else { return [] }
        var actions: [SidecarQuickAction] = []
        switch context.kind {
        case .file:
            actions.append(contentsOf: Self.fileActions)
        case .gitDiff:
            actions.append(contentsOf: Self.gitDiffActions)
        case .terminal, .gemma:
            break
        }
        if let selection = context.editorSelection,
           !selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            actions.append(Self.editorSelectionAction)
        }
        actions.append(contentsOf: terminalActions.quickActions(for: context))
        actions.append(contentsOf: briefing.quickActions(for: context))
        return actions
    }

    func start() {
        guard timerTask == nil else { return }
        terminalTabs.setTerminalCommandFinishedHandler { [weak self] exitCode in
            self?.handleCommandFinished(exitCode: exitCode)
        }
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(GemmaSidecarModel.tickInterval))
                guard !Task.isCancelled, let self else { return }
                self.journal.tick()
                self.intentGuard.tick()
                self.whisper.tick()
            }
        }
        AppLogger.agent.info("Started Gemma sidecar")
    }

    func stop() {
        timerTask?.cancel()
        timerTask = nil
        terminalTabs.setTerminalCommandFinishedHandler(nil)
        interactive.close()
        let runner = background
        Task { await runner.cancelAll() }
        guardian.cleanup()
        journal.cleanup()
        whisper.cleanup()
    }

    func handleCommandFinished(exitCode: Int32) {
        guardian.handleCommandFinished(exitCode: exitCode)
    }

    /// Resets the interactive session only. Never touches the chat tab.
    func clear() {
        interactive.clear()
    }

    isolated deinit {
        timerTask?.cancel()
        interactive.close()
    }
}

extension GemmaSidecarModel {
    static let fileActions: [SidecarQuickAction] = [
        SidecarQuickAction(
            id: "file.explain",
            title: "Explain File",
            systemImage: "doc.text.magnifyingglass",
            prompt: "Explain what this file does and its role in the workspace. Cite the path and line numbers."
        ),
        SidecarQuickAction(
            id: "file.summarize",
            title: "Summarize",
            systemImage: "list.bullet.rectangle",
            prompt: "Summarize this file as a short bulleted list of its key responsibilities."
        ),
        SidecarQuickAction(
            id: "file.findUsages",
            title: "Find Usages",
            systemImage: "magnifyingglass",
            prompt: "Find where the main symbols defined in this file are used across the workspace."
        )
    ]

    static let gitDiffActions: [SidecarQuickAction] = [
        SidecarQuickAction(
            id: "gitDiff.review",
            title: "Review Diff",
            systemImage: "checklist",
            prompt: "Review this Git diff for bugs, risky changes, and issues. Be concise."
        ),
        SidecarQuickAction(
            id: "gitDiff.commitMessage",
            title: "Commit Message",
            systemImage: "text.badge.checkmark",
            prompt: "Suggest a concise Conventional Commit message for this diff."
        )
    ]

    static let editorSelectionAction = SidecarQuickAction(
        id: "editor.explainSelection",
        title: "Explain Selection",
        systemImage: "text.cursor",
        prompt: "Explain the selected code and what it does."
    )
}
