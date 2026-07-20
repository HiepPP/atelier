import Foundation
import Observation

/// TASK-004 - Terminal quick actions.
///
/// Feature builder: implement `quickActions(for:)` so that when the selected tab
/// is a terminal it returns one-shot `SidecarQuickAction` prompts such as
/// "Explain last error" and "Explain command". Read terminal output through
/// `services.readTerminalOutput(_:)` (or let the prompt trigger the read-only
/// `read_terminal_output` tool) and prepend nothing else; the interactive model
/// injects tab context. Return `[]` for non-terminal contexts.
///
/// Edit ONLY this file. Do not modify GemmaSidecarModel, GemmaSidecarView, or any
/// shared file; if you need a shared change, return BLOCKED with the exact change.
@MainActor
@Observable
final class SidecarTerminalActionsModel {
    private let services: SidecarServices

    init(services: SidecarServices) {
        self.services = services
    }

    /// Terminal-tab quick actions. Each prompt instructs Gemma to call the
    /// read-only `read_terminal_output` tool and analyze the recent lines. Tab
    /// context (including the working directory) is injected by the interactive
    /// model, so the prompts add nothing beyond the analysis instruction.
    func quickActions(for context: GemmaSidecarTabContext?) -> [SidecarQuickAction] {
        guard let context, context.kind == .terminal else { return [] }
        return Self.terminalActions
    }
}

extension SidecarTerminalActionsModel {
    static let terminalActions: [SidecarQuickAction] = [
        SidecarQuickAction(
            id: "terminal.explainError",
            title: "Explain Last Error",
            systemImage: "exclamationmark.triangle",
            prompt: """
            Call the read_terminal_output tool to read the recent output of the \
            selected terminal. Find the most recent error or failed command, then \
            explain what caused it and how to fix it. Be concise and quote the \
            relevant output lines. If there is no error, say so.
            """
        ),
        SidecarQuickAction(
            id: "terminal.explainCommand",
            title: "Explain Last Command",
            systemImage: "terminal",
            prompt: """
            Call the read_terminal_output tool to read the recent output of the \
            selected terminal. Explain what the last command did and what its \
            result was, based only on the output. Be concise.
            """
        )
    ]
}
