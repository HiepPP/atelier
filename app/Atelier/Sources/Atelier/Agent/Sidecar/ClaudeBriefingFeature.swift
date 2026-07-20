import AppKit
import Observation
import SwiftUI

/// TASK-006 - Claude Code Briefing.
///
/// Produces a self-contained handoff prompt a developer can hand to Claude Code
/// running in the terminal. On demand it runs ONE bounded, read-only background
/// Gemma call that gathers the real work state (files being changed, the git diff
/// summary, and the recent terminal tail) and asks Gemma to write a concise prompt
/// describing that state. The generated prompt is shown with Copy and Paste
/// controls; Paste inserts the text into the selected terminal without sending
/// Return, so nothing executes.
///
/// The trigger lives in `ClaudeBriefingView` because the shared quick-action row
/// routes actions through `runInteractive`, which cannot drive the background
/// call. `quickActions(for:)` still offers a Brief action so the interactive
/// response area can produce a conversational briefing.
///
/// Edit ONLY this file. Do not modify GemmaSidecarModel, GemmaSidecarView, or any
/// shared file; if you need a shared change, return BLOCKED with the exact change.
enum ClaudeBriefingPhase: Equatable {
    case idle
    case generating
    case ready(String)
    case failed(String)
}

@MainActor
@Observable
final class ClaudeBriefingModel {
    private static let terminalTailLines = 80
    // Referenced from the nonisolated `briefingInstruction`, so these bounds must
    // be reachable off the main actor. They are immutable Sendable literals.
    private nonisolated static let maxTerminalTailCharacters = 4_000
    private nonisolated static let maxDiffStatCharacters = 4_000
    private nonisolated static let maxChangedFiles = 40

    private let services: SidecarServices

    private(set) var phase: ClaudeBriefingPhase = .idle
    private(set) var actionNote: String?

    private var task: Task<Void, Never>?

    init(services: SidecarServices) {
        self.services = services
    }

    /// The selected tab context only when it is a terminal tab; otherwise nil.
    var activeTerminalContext: GemmaSidecarTabContext? {
        guard let context = services.currentContext(), context.kind == .terminal else {
            return nil
        }
        return context
    }

    /// Offers a conversational Brief action in the shared quick-action row when a
    /// terminal tab is selected. The container sends this prompt through
    /// `runInteractive`, streaming a briefing into the response area.
    func quickActions(for context: GemmaSidecarTabContext?) -> [SidecarQuickAction] {
        guard let context, context.kind == .terminal else { return [] }
        return [Self.briefQuickAction]
    }

    /// Starts one bounded background run that produces a paste-ready handoff
    /// prompt. Ignored while a run is already in flight or when no terminal tab is
    /// selected.
    func generate() {
        guard task == nil else { return }
        guard activeTerminalContext != nil else { return }
        actionNote = nil
        phase = .generating
        task = Task { [weak self] in
            await self?.runGenerate()
        }
    }

    /// Cancels an in-flight run and returns to the idle state.
    func cancel() {
        task?.cancel()
        task = nil
        if phase == .generating {
            phase = .idle
        }
    }

    /// Copies the generated briefing to the pasteboard.
    func copyBriefing() {
        guard case .ready(let text) = phase else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        actionNote = "Copied briefing to clipboard."
    }

    /// Pastes the generated briefing into the selected terminal without sending
    /// Return, so Claude Code does not run until the user presses it.
    func pasteBriefing() {
        guard case .ready(let text) = phase else { return }
        let pasted = services.pasteIntoTerminal(text)
        actionNote = pasted
            ? "Pasted into terminal - press Return to send."
            : "No terminal selected to paste into."
    }

    private func runGenerate() async {
        guard let context = activeTerminalContext else {
            phase = .idle
            task = nil
            return
        }

        let diffStat = await services.diffStat()
        if Task.isCancelled { return }
        let changedFiles = await services.changedFiles()
        if Task.isCancelled { return }
        let terminalTail = await services.readTerminalOutput(Self.terminalTailLines) ?? ""
        if Task.isCancelled { return }

        let instruction = Self.briefingInstruction(
            context: context,
            diffStat: diffStat,
            changedFiles: changedFiles,
            terminalTail: terminalTail
        )

        do {
            let output = try await services.runBackground(instruction)
            if Task.isCancelled { return }
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            phase = trimmed.isEmpty
                ? .failed("Gemma returned an empty briefing.")
                : .ready(trimmed)
            AppLogger.agent.info("Gemma sidecar generated a Claude briefing")
        } catch is CancellationError {
            // Our own cancel(); phase was already reset by cancel().
        } catch let error as OllamaCloudError where error == .cancelled {
            // Preempted by another serialized background run; allow a retry.
            if Task.isCancelled { return }
            phase = .idle
        } catch let error as GemmaAgentRuntimeError where error == .cancelled {
            if Task.isCancelled { return }
            phase = .idle
        } catch {
            if Task.isCancelled { return }
            phase = .failed(Self.errorText(error))
        }
        task = nil
    }

    private nonisolated static func errorText(_ error: Error) -> String {
        if let cloud = error as? OllamaCloudError {
            var text = cloud.errorDescription ?? "Gemma could not build the briefing."
            if let recovery = cloud.recoverySuggestion {
                text += " " + recovery
            }
            return text
        }
        return "Gemma could not build the briefing."
    }

    private nonisolated static func briefingInstruction(
        context: GemmaSidecarTabContext,
        diffStat: String,
        changedFiles: [String],
        terminalTail: String
    ) -> String {
        var lines: [String] = [
            "Write a single, self-contained handoff prompt for Claude Code, a terminal coding assistant, so it can continue the current work in this repository.",
            "",
            "Rules for the prompt you write:",
            "- 4 to 8 sentences of plain text. No markdown headings, no preamble, no surrounding quotes.",
            "- Name the specific files currently being changed.",
            "- Summarize what the diff changes so far.",
            "- Note anything still in progress based on the recent terminal output.",
            "- End with one clear next objective.",
            "Output only the handoff prompt text and nothing else.",
            "",
            "Current work state (read-only facts):",
            "Active tab: \(context.title) (\(context.status))",
            "Working directory: \(context.workingDirectory ?? "unknown")"
        ]
        if let filePath = context.filePath {
            lines.append("File in focus: \(filePath)")
        }

        lines.append("Changed files:")
        if changedFiles.isEmpty {
            lines.append("(none reported)")
        } else {
            let capped = changedFiles.prefix(maxChangedFiles)
            lines.append(contentsOf: capped.map { "- \($0)" })
            if changedFiles.count > maxChangedFiles {
                lines.append("- ... and \(changedFiles.count - maxChangedFiles) more")
            }
        }

        let trimmedStat = diffStat.trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append("Diff summary (git diff --stat):")
        lines.append(trimmedStat.isEmpty ? "(no unstaged changes)" : boundedTail(trimmedStat, limit: maxDiffStatCharacters))

        let trimmedTail = terminalTail.trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append("Recent terminal output (tail):")
        lines.append(trimmedTail.isEmpty ? "(no terminal output captured)" : boundedTail(trimmedTail, limit: maxTerminalTailCharacters))

        return lines.joined(separator: "\n")
    }

    private nonisolated static func boundedTail(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.suffix(limit))
    }

    static let briefQuickAction = SidecarQuickAction(
        id: "briefing.brief",
        title: "Brief for Claude",
        systemImage: "text.append",
        prompt: """
        Summarize the current work state in this repository as a short briefing I can hand to Claude Code. \
        Use your tools to read the git diff (read_git_diff) and the recent terminal output (read_terminal_output). \
        Name the files being changed, what the diff does, anything still in progress, and the next objective. \
        Keep it to a few sentences of plain text.
        """
    )

    isolated deinit {
        task?.cancel()
    }
}

struct ClaudeBriefingView: View {
    let model: ClaudeBriefingModel

    var body: some View {
        switch presentation {
        case .hidden, .idle:
            EmptyView()
        case .generating:
            section { generatingContent }
        case .ready(let text):
            section { readyContent(text) }
        case .failed(let message):
            section { failedContent(message) }
        }
    }

    private enum Presentation: Equatable {
        case hidden
        case idle
        case generating
        case ready(String)
        case failed(String)
    }

    private var presentation: Presentation {
        guard model.activeTerminalContext != nil else { return .hidden }
        switch model.phase {
        case .idle: return .idle
        case .generating: return .generating
        case .ready(let text): return .ready(text)
        case .failed(let message): return .failed(message)
        }
    }

    private func section<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(AtelierMetrics.spaceM)
            .frame(maxWidth: .infinity, alignment: .leading)
            .atelierCard()
            .accessibilityElement(children: .contain)
    }

    private var headerLabel: some View {
        Label("Claude handoff", systemImage: "terminal")
            .atelierFont(size: AtelierTypography.caption, weight: .semibold)
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }

    private var generatingContent: some View {
        HStack(spacing: AtelierMetrics.spaceS) {
            ProgressView()
                .controlSize(.small)
            Text("Building Claude briefing...")
                .atelierFont(size: AtelierTypography.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button(action: model.cancel) {
                Text("Cancel")
            }
            .buttonStyle(AtelierGhostButtonStyle())
            .accessibilityLabel("Cancel briefing")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Building Claude briefing")
    }

    private func readyContent(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: AtelierMetrics.spaceXS) {
            HStack(spacing: AtelierMetrics.spaceXS) {
                headerLabel
                Spacer(minLength: 0)
                Button(action: model.copyBriefing) {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(AtelierGhostButtonStyle())
                .accessibilityLabel("Copy briefing")
                Button(action: model.pasteBriefing) {
                    Label("Paste", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(AtelierGhostButtonStyle(tint: AtelierTheme.accent))
                .accessibilityLabel("Paste briefing into terminal")
                .help("Insert into the terminal without running it")
            }

            ScrollView {
                Text(text)
                    .atelierFont(size: AtelierTypography.caption, design: .monospaced)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(AtelierMetrics.spaceS)
            }
            .frame(maxHeight: 132)
            .atelierCard(fill: AtelierTheme.editor)

            HStack(spacing: AtelierMetrics.spaceXS) {
                if let note = model.actionNote {
                    Text(note)
                        .atelierFont(size: AtelierTypography.micro)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button(action: model.generate) {
                    Text("Regenerate")
                }
                .buttonStyle(AtelierGhostButtonStyle())
                .accessibilityLabel("Regenerate briefing")
            }
        }
    }

    private func failedContent(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: AtelierMetrics.spaceXS) {
            HStack(spacing: AtelierMetrics.spaceXS) {
                Label("Briefing unavailable", systemImage: "exclamationmark.triangle")
                    .atelierFont(size: AtelierTypography.caption, weight: .semibold)
                    .foregroundStyle(AtelierTheme.danger)
                Spacer(minLength: 0)
                Button(action: model.generate) {
                    Text("Retry")
                }
                .buttonStyle(AtelierGhostButtonStyle())
                .accessibilityLabel("Retry briefing")
            }
            Text(message)
                .atelierFont(size: AtelierTypography.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
