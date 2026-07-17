import Foundation

nonisolated enum WorkspaceToolName: String, Codable, CaseIterable, Sendable {
    case searchWorkspace = "search_workspace"
    case readFile = "read_file"
    case readGitDiff = "read_git_diff"
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

nonisolated struct WorkspaceToolResult: Equatable, Sendable {
    let content: String
    let referencedFiles: [String]
    let truncated: Bool

    init(content: String, referencedFiles: [String] = [], truncated: Bool = false) {
        self.content = content
        self.referencedFiles = referencedFiles
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
        case .cancelled: return "Workspace tool cancelled."
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
        )
    ]
}
