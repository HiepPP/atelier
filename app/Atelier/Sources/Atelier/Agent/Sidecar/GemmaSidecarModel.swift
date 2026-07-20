import Foundation
import Observation

/// Serializes background Gemma runs so at most one executes at a time. A new run
/// cancels any in-flight run, then waits for it to unwind before starting. The
/// runtime history is reset before each run so background calls stay one-shot.
actor SidecarBackgroundRunner {
    private let runtime: GemmaAgentRuntime
    private var chain: Task<Void, Never>

    init(runtime: GemmaAgentRuntime) {
        self.runtime = runtime
        self.chain = Task {}
    }

    func run(prompt: String) async throws -> String {
        let previous = chain
        await runtime.cancel()
        let runtime = self.runtime
        let work = Task<String, Error> {
            _ = await previous.value
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
        chain = Task { _ = try? await work.value }
        return try await work.value
    }

    func cancelAll() async {
        chain.cancel()
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
