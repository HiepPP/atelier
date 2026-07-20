import Foundation

nonisolated protocol WorkspaceToolExecuting: Sendable {
    func execute(_ call: OllamaToolCall) async throws -> WorkspaceToolResult
}

actor WorkspaceToolExecutor: WorkspaceToolExecuting {
    private static let maximumReadBytes = 256_000
    private static let maximumReadLines = 400
    private static let maximumSearchMatches = 100
    private static let maximumSearchFileBytes = 1_000_000
    private static let maximumGitBytes = 500_000
    private static let maximumTerminalLines = 400
    private static let defaultTerminalLines = 200
    private static let maximumTerminalCharacters = 100_000

    private let workspaceRoot: URL
    private let gitService: GitService
    private let terminalSnapshot: (@MainActor @Sendable (Int) -> String?)?

    init(
        workspaceRoot: URL,
        gitService: GitService = GitService(),
        terminalSnapshot: (@MainActor @Sendable (Int) -> String?)? = nil
    ) {
        self.workspaceRoot = workspaceRoot.standardizedFileURL.resolvingSymlinksInPath()
        self.gitService = gitService
        self.terminalSnapshot = terminalSnapshot
    }

    func execute(_ call: OllamaToolCall) async throws -> WorkspaceToolResult {
        do {
            try Task.checkCancellation()
            guard let name = WorkspaceToolName(rawValue: call.function.name) else {
                throw WorkspaceToolError.unknownTool(call.function.name)
            }
            let data = try encodedArguments(call.function.arguments)
            switch name {
            case .searchWorkspace:
                let input = try JSONDecoder().decode(WorkspaceSearchInput.self, from: data)
                return try await search(input)
            case .readFile:
                let input = try JSONDecoder().decode(WorkspaceReadFileInput.self, from: data)
                return try await read(input)
            case .readGitDiff:
                let input = try JSONDecoder().decode(WorkspaceGitDiffInput.self, from: data)
                return try await gitDiff(input)
            case .readTerminalOutput:
                let input = try JSONDecoder().decode(WorkspaceReadTerminalInput.self, from: data)
                return try await readTerminalOutput(input)
            }
        } catch is CancellationError {
            throw WorkspaceToolError.cancelled
        } catch let error as WorkspaceToolError {
            throw error
        } catch {
            throw WorkspaceToolError.invalidArguments(Self.safeError(error))
        }
    }

    private func readTerminalOutput(_ input: WorkspaceReadTerminalInput) async throws -> WorkspaceToolResult {
        guard let terminalSnapshot else { throw WorkspaceToolError.noTerminalSelected }
        let lines = min(max(1, input.lines ?? Self.defaultTerminalLines), Self.maximumTerminalLines)
        guard let snapshot = await terminalSnapshot(lines) else {
            throw WorkspaceToolError.noTerminalSelected
        }
        try Task.checkCancellation()
        let truncated = snapshot.count > Self.maximumTerminalCharacters
        let bounded = truncated
            ? String(snapshot.prefix(Self.maximumTerminalCharacters))
            : snapshot
        return WorkspaceToolResult(
            content: bounded.isEmpty ? "Terminal has no output yet." : bounded,
            truncated: truncated
        )
    }

    private func search(_ input: WorkspaceSearchInput) async throws -> WorkspaceToolResult {
        let query = input.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, query.count <= 500 else {
            throw WorkspaceToolError.invalidArguments("Search query is empty or too long.")
        }
        return try Self.performSearch(query: query, root: workspaceRoot)
    }

    private func read(_ input: WorkspaceReadFileInput) async throws -> WorkspaceToolResult {
        let url = try validatedFileURL(for: input.path)
        let startLine = max(1, input.startLine ?? 1)
        let lineCount = min(max(1, input.lineCount ?? Self.maximumReadLines), Self.maximumReadLines)
        return try Self.performRead(url: url, startLine: startLine, lineCount: lineCount)
    }

    private func gitDiff(_ input: WorkspaceGitDiffInput) async throws -> WorkspaceToolResult {
        var arguments = ["diff"]
        if input.staged == true { arguments.append("--cached") }
        arguments.append(contentsOf: ["--no-color", "--no-ext-diff"])
        do {
            let data = try await gitService.run(
                arguments: arguments,
                workspacePath: workspaceRoot.path,
                maxOutputBytes: Self.maximumGitBytes
            )
            try Task.checkCancellation()
            let text = String(decoding: data, as: UTF8.self)
            return WorkspaceToolResult(
                content: text.isEmpty ? "No Git diff." : text,
                truncated: data.count >= Self.maximumGitBytes
            )
        } catch is CancellationError {
            throw WorkspaceToolError.cancelled
        } catch {
            throw WorkspaceToolError.gitFailed(Self.safeError(error))
        }
    }

    private func validatedFileURL(for path: String) throws -> URL {
        guard !path.isEmpty, !path.contains("\0") else { throw WorkspaceToolError.invalidPath }
        let proposed: URL
        if path.hasPrefix("/") {
            proposed = URL(fileURLWithPath: path)
        } else {
            proposed = workspaceRoot.appending(path: path)
        }
        let resolved = proposed.standardizedFileURL.resolvingSymlinksInPath()
        guard Self.contains(resolved, in: workspaceRoot) else {
            throw WorkspaceToolError.outsideWorkspace
        }
        guard !Self.isSensitive(resolved, relativeTo: workspaceRoot) else {
            throw WorkspaceToolError.sensitivePath
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            throw WorkspaceToolError.notFile
        }
        return resolved
    }

    private func encodedArguments(_ arguments: [String: OllamaJSONValue]) throws -> Data {
        do {
            return try JSONEncoder().encode(arguments)
        } catch {
            throw WorkspaceToolError.invalidArguments(Self.safeError(error))
        }
    }

    private nonisolated static func performRead(
        url: URL,
        startLine: Int,
        lineCount: Int
    ) throws -> WorkspaceToolResult {
        try Task.checkCancellation()
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw WorkspaceToolError.unreadable(safeError(error))
        }
        defer { try? handle.close() }
        let data: Data
        do {
            data = try handle.read(upToCount: maximumReadBytes + 1) ?? Data()
        } catch {
            throw WorkspaceToolError.unreadable(safeError(error))
        }
        try Task.checkCancellation()
        guard !data.prefix(8_192).contains(0) else { throw WorkspaceToolError.notFile }
        let wasByteTruncated = data.count > maximumReadBytes
        let text = String(decoding: data.prefix(maximumReadBytes), as: UTF8.self)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let lower = min(max(0, startLine - 1), lines.count)
        let upper = min(lines.count, lower + lineCount)
        let numbered = lines[lower..<upper].enumerated().map { offset, line in
            "\(lower + offset + 1): \(line)"
        }.joined(separator: "\n")
        let truncated = wasByteTruncated || lower > 0 || upper < lines.count
        return WorkspaceToolResult(
            content: numbered.isEmpty ? "File is empty." : numbered,
            referencedFiles: [url.path],
            truncated: truncated
        )
    }

    private nonisolated static func performSearch(
        query: String,
        root: URL
    ) throws -> WorkspaceToolResult {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else {
            throw WorkspaceToolError.searchFailed("Could not enumerate workspace.")
        }

        var matches: [String] = []
        var files: [String] = []
        var truncated = false
        while let url = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            let relative = relativePath(url, root: root)
            if shouldSkipSearchPath(relative) {
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    enumerator.skipDescendants()
                }
                continue
            }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true,
                  (values?.fileSize ?? Int.max) <= maximumSearchFileBytes,
                  !isSensitive(url.resolvingSymlinksInPath(), relativeTo: root) else {
                continue
            }
            guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
                  !data.prefix(8_192).contains(0),
                  let text = String(data: data, encoding: .utf8) else {
                continue
            }
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                try Task.checkCancellation()
                guard line.localizedCaseInsensitiveContains(query) else { continue }
                matches.append("\(relative):\(index + 1): \(String(line.prefix(500)))")
                if !files.contains(relative) { files.append(relative) }
                if matches.count == maximumSearchMatches {
                    truncated = true
                    break
                }
            }
            if truncated { break }
        }
        return WorkspaceToolResult(
            content: matches.isEmpty ? "No matches." : matches.joined(separator: "\n"),
            referencedFiles: files,
            truncated: truncated
        )
    }

    private nonisolated static func contains(_ url: URL, in root: URL) -> Bool {
        let rootComponents = root.standardizedFileURL.pathComponents
        let candidateComponents = url.standardizedFileURL.pathComponents
        return candidateComponents.starts(with: rootComponents)
    }

    private nonisolated static func relativePath(_ url: URL, root: URL) -> String {
        let rootComponents = root.pathComponents
        return url.pathComponents.dropFirst(rootComponents.count).joined(separator: "/")
    }

    private nonisolated static func isSensitive(_ url: URL, relativeTo root: URL) -> Bool {
        let relative = relativePath(url, root: root).lowercased()
        let components = relative.split(separator: "/").map(String.init)
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

    private nonisolated static func shouldSkipSearchPath(_ relative: String) -> Bool {
        let components = relative.lowercased().split(separator: "/")
        return components.contains(".build") || components.contains("dist") ||
            components.contains("node_modules")
    }

    private nonisolated static func safeError(_ error: Error) -> String {
        String(error.localizedDescription.prefix(256))
    }
}
