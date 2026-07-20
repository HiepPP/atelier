import Foundation

/// Context describing the selected center tab, injected into each sidecar prompt.
nonisolated struct GemmaSidecarTabContext: Equatable, Sendable {
    let kind: TerminalTabInspectorKind
    let title: String
    let status: String
    let systemImage: String
    let filePath: String?
    let workingDirectory: String?
    let gitDiffPath: String?
    let editorSelection: String?

    init(
        kind: TerminalTabInspectorKind,
        title: String,
        status: String,
        systemImage: String,
        filePath: String? = nil,
        workingDirectory: String? = nil,
        gitDiffPath: String? = nil,
        editorSelection: String? = nil
    ) {
        self.kind = kind
        self.title = title
        self.status = status
        self.systemImage = systemImage
        self.filePath = filePath
        self.workingDirectory = workingDirectory
        self.gitDiffPath = gitDiffPath
        self.editorSelection = editorSelection
    }
}

/// A one-shot prompt the user can send into the interactive response area.
nonisolated struct SidecarQuickAction: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let systemImage: String
    let prompt: String

    init(id: String, title: String, systemImage: String, prompt: String) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.prompt = prompt
    }
}

/// Read-only service surface shared by every sidecar feature. Features hold this
/// value and call its members; they never reach into the workspace directly.
///
/// All members are read-only. `runBackground` runs one bounded, serialized Gemma
/// call at a time on a dedicated background runtime and throws on transport error
/// or cancellation. `runInteractive` sends a one-shot prompt to the primary
/// response area. `pasteIntoTerminal` never sends Enter.
@MainActor
struct SidecarServices {
    let currentContext: () -> GemmaSidecarTabContext?
    let runBackground: (_ prompt: String) async throws -> String
    let runInteractive: (_ prompt: String) -> Void
    let readTerminalOutput: (_ lines: Int) async -> String?
    let unstagedDiff: () async -> String
    let changedFiles: () async -> [String]
    let diffStat: () async -> String
    let pasteIntoTerminal: (_ text: String) -> Bool
    let isOllamaConfigured: () -> Bool
}

/// Builds the context block prepended to sidecar prompts. Pure and deterministic
/// so it can be unit tested without a runtime. Never prepends when no tab is
/// selected.
nonisolated enum GemmaSidecarContextComposer {
    static func contextBlock(for context: GemmaSidecarTabContext?) -> String? {
        guard let context else { return nil }
        var lines: [String] = ["[Atelier context]"]
        lines.append("Active tab: \(context.kind.rawValue) - \(context.title) (\(context.status))")
        if let filePath = context.filePath { lines.append("File: \(filePath)") }
        if let workingDirectory = context.workingDirectory {
            lines.append("Working directory: \(workingDirectory)")
        }
        if let gitDiffPath = context.gitDiffPath {
            lines.append("Git diff target: \(gitDiffPath)")
        }
        if let selection = context.editorSelection,
           !selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Editor selection:")
            lines.append(selection)
        }
        return lines.joined(separator: "\n")
    }

    static func compose(prompt: String, context: GemmaSidecarTabContext?) -> String {
        guard let block = contextBlock(for: context) else { return prompt }
        return block + "\n\n" + prompt
    }
}
