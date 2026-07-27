import Foundation

nonisolated enum WorkspaceToolName: String, Codable, CaseIterable, Sendable {
    case searchWorkspace = "search_workspace"
    case readFile = "read_file"
    case readGitDiff = "read_git_diff"
    case readTerminalOutput = "read_terminal_output"
}

nonisolated struct WorkspaceSearchInput: Codable, Equatable, Sendable {
    let query: String
}

nonisolated struct WorkspaceReadFileInput: Codable, Equatable, Sendable {
    let path: String
    let startLine: Int?
    let lineCount: Int?

    enum CodingKeys: String, CodingKey {
        case path
        case startLine = "start_line"
        case lineCount = "line_count"
    }
}

nonisolated struct WorkspaceGitDiffInput: Codable, Equatable, Sendable {
    let staged: Bool?
}

nonisolated struct WorkspaceReadTerminalInput: Codable, Equatable, Sendable {
    let lines: Int?
}

nonisolated struct WorkspaceToolReference: Identifiable, Equatable, Sendable {
    let path: String
    let lineNumber: Int
    let excerpt: String

    var id: String { "\(path):\(lineNumber)" }
}

nonisolated struct WorkspaceToolResult: Equatable, Sendable {
    let content: String
    let referencedFiles: [String]
    let references: [WorkspaceToolReference]
    let truncated: Bool

    init(
        content: String,
        referencedFiles: [String] = [],
        references: [WorkspaceToolReference] = [],
        truncated: Bool = false
    ) {
        self.content = content
        var files = referencedFiles
        for reference in references where !files.contains(reference.path) {
            files.append(reference.path)
        }
        self.referencedFiles = files
        self.references = references
        self.truncated = truncated
    }
}

nonisolated enum WorkspaceToolError: LocalizedError, Equatable, Sendable {
    case unknownTool(String)
    case invalidArguments(String)
    case invalidPath
    case outsideWorkspace
    case sensitivePath
    case notFile
    case unreadable(String)
    case searchFailed(String)
    case gitFailed(String)
    case noTerminalSelected
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unknownTool(let name): return "Unknown read-only tool: \(name)"
        case .invalidArguments: return "Tool arguments are invalid."
        case .invalidPath: return "The requested path is invalid."
        case .outsideWorkspace: return "The requested path is outside the workspace."
        case .sensitivePath: return "Access to this sensitive path is blocked."
        case .notFile: return "The requested path is not a readable file."
        case .unreadable: return "The requested file could not be read."
        case .searchFailed: return "Workspace search failed."
        case .gitFailed: return "Git diff could not be read."
        case .noTerminalSelected: return "No terminal tab is selected to read output from."
        case .cancelled: return "Workspace tool cancelled."
        }
    }
}

nonisolated enum WorkspaceToolPathPolicy {
    static func isSensitive(_ url: URL, relativeTo root: URL) -> Bool {
        let rootComponents = root.standardizedFileURL.pathComponents
        let components = url.standardizedFileURL.pathComponents
        guard components.starts(with: rootComponents) else { return true }
        let relative = components.dropFirst(rootComponents.count).joined(separator: "/")
        return isSensitive(relativePath: relative)
    }

    static func isSensitive(relativePath: String) -> Bool {
        let components = relativePath.lowercased().split(separator: "/").map(String.init)
        if components.contains(".git") { return true }
        return components.contains { component in
            component == ".env" || component.hasPrefix(".env.") ||
                component == "id_rsa" || component == "id_ed25519" ||
                component == "credentials" || component == "credentials.json" ||
                component == "client_secrets.json" || component == "secrets.json" ||
                component == "token.json" || component == ".netrc" || component == ".npmrc" ||
                component.hasSuffix(".pem") || component.hasSuffix(".p12") ||
                component.hasSuffix(".key")
        }
    }
}

nonisolated extension WorkspaceToolName {
    static let definitions: [OllamaToolDefinition] = [
        OllamaToolDefinition(
            function: OllamaFunctionDefinition(
                name: searchWorkspace.rawValue,
                description: "Search text files in the active workspace for a literal query.",
                parameters: OllamaToolParameters(
                    properties: [
                        "query": OllamaToolProperty(
                            type: "string",
                            description: "Literal text to find in workspace files."
                        )
                    ],
                    required: ["query"]
                )
            )
        ),
        OllamaToolDefinition(
            function: OllamaFunctionDefinition(
                name: readFile.rawValue,
                description: "Read a bounded line range from a workspace file.",
                parameters: OllamaToolParameters(
                    properties: [
                        "path": OllamaToolProperty(
                            type: "string",
                            description: "Workspace-relative file path."
                        ),
                        "start_line": OllamaToolProperty(
                            type: "integer",
                            description: "Optional one-based first line."
                        ),
                        "line_count": OllamaToolProperty(
                            type: "integer",
                            description: "Optional number of lines, capped by Atelier."
                        )
                    ],
                    required: ["path"]
                )
            )
        ),
        OllamaToolDefinition(
            function: OllamaFunctionDefinition(
                name: readGitDiff.rawValue,
                description: "Read the bounded unstaged or staged Git diff for this workspace.",
                parameters: OllamaToolParameters(
                    properties: [
                        "staged": OllamaToolProperty(
                            type: "boolean",
                            description: "Use true for the staged diff. Defaults to false."
                        )
                    ],
                    required: []
                )
            )
        ),
        OllamaToolDefinition(
            function: OllamaFunctionDefinition(
                name: readTerminalOutput.rawValue,
                description: "Read the last lines of the selected terminal's output.",
                parameters: OllamaToolParameters(
                    properties: [
                        "lines": OllamaToolProperty(
                            type: "integer",
                            description: "Optional number of trailing lines, capped at 400 by Atelier."
                        )
                    ],
                    required: []
                )
            )
        )
    ]
}
