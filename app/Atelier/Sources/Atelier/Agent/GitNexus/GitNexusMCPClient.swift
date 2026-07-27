import Foundation
import MCP

#if canImport(System)
import System
#else
@preconcurrency import SystemPackage
#endif

nonisolated struct GitNexusQueryInput: Codable, Equatable, Sendable {
    let searchQuery: String
    let taskContext: String?
    let goal: String?

    enum CodingKeys: String, CodingKey {
        case searchQuery = "search_query"
        case taskContext = "task_context"
        case goal
    }
}

nonisolated struct GitNexusContextInput: Codable, Equatable, Sendable {
    let name: String?
    let uid: String?
    let filePath: String?
    let kind: String?

    enum CodingKeys: String, CodingKey {
        case name
        case uid
        case filePath = "file_path"
        case kind
    }
}

nonisolated struct GitNexusCodeIntelligenceResult: Equatable, Sendable {
    let content: String
    let references: [WorkspaceToolReference]
}

nonisolated protocol GitNexusCodeIntelligence: Sendable {
    func query(_ input: GitNexusQueryInput) async throws -> GitNexusCodeIntelligenceResult
    func context(_ input: GitNexusContextInput) async throws -> GitNexusCodeIntelligenceResult
    func stop() async
}

nonisolated enum GitNexusMCPError: LocalizedError, Equatable, Sendable {
    case unavailable
    case missingIndex
    case invalidArguments
    case startupFailed
    case requestFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "GitNexus is not installed for this workspace."
        case .missingIndex:
            return "GitNexus has not indexed this workspace."
        case .invalidArguments:
            return "GitNexus tool arguments are invalid."
        case .startupFailed:
            return "GitNexus MCP could not start."
        case .requestFailed:
            return "GitNexus MCP request failed."
        case .invalidResponse:
            return "GitNexus returned an invalid response."
        }
    }
}

actor GitNexusMCPClient: GitNexusCodeIntelligence {
    private static let requestTimeout = Duration.seconds(15)
    private static let maximumResultCharacters = 16_000

    private let workspaceRoot: URL
    private var client: Client?
    private var transport: StdioTransport?
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?

    init(workspaceRoot: URL) {
        self.workspaceRoot = workspaceRoot.standardizedFileURL.resolvingSymlinksInPath()
    }

    func query(_ input: GitNexusQueryInput) async throws -> GitNexusCodeIntelligenceResult {
        let searchQuery = Self.bounded(input.searchQuery, maximum: 500)
        guard !searchQuery.isEmpty else { throw GitNexusMCPError.invalidArguments }
        var arguments: [String: Value] = [
            "repo": .string(workspaceRoot.path),
            "search_query": .string(searchQuery),
            "limit": .int(5),
            "max_symbols": .int(8),
            "include_content": .bool(false),
            "maxTokens": .int(5_000)
        ]
        if let taskContext = input.taskContext.map({ Self.bounded($0, maximum: 500) }),
           !taskContext.isEmpty {
            arguments["task_context"] = .string(taskContext)
        }
        if let goal = input.goal.map({ Self.bounded($0, maximum: 500) }), !goal.isEmpty {
            arguments["goal"] = .string(goal)
        }
        let text = try await callTool(name: "query", arguments: arguments)
        return try GitNexusResponseParser.query(
            text: text,
            workspaceRoot: workspaceRoot,
            searchMode: searchMode()
        )
    }

    func context(_ input: GitNexusContextInput) async throws -> GitNexusCodeIntelligenceResult {
        let name = input.name.map { Self.bounded($0, maximum: 500) }
        let uid = input.uid.map { Self.bounded($0, maximum: 1_000) }
        guard name?.isEmpty == false || uid?.isEmpty == false else {
            throw GitNexusMCPError.invalidArguments
        }
        var arguments: [String: Value] = [
            "repo": .string(workspaceRoot.path),
            "include_content": .bool(false),
            "maxTokens": .int(5_000)
        ]
        if let name, !name.isEmpty { arguments["name"] = .string(name) }
        if let uid, !uid.isEmpty { arguments["uid"] = .string(uid) }
        if let filePath = input.filePath.map({ Self.bounded($0, maximum: 1_000) }),
           !filePath.isEmpty {
            arguments["file_path"] = .string(filePath)
        }
        if let kind = input.kind.map({ Self.bounded($0, maximum: 100) }), !kind.isEmpty {
            arguments["kind"] = .string(kind)
        }
        let text = try await callTool(name: "context", arguments: arguments)
        return try GitNexusResponseParser.context(text: text, workspaceRoot: workspaceRoot)
    }

    func stop() async {
        await client?.disconnect()
        client = nil
        await transport?.disconnect()
        transport = nil
        try? inputPipe?.fileHandleForWriting.close()
        try? outputPipe?.fileHandleForReading.close()
        inputPipe = nil
        outputPipe = nil
        if let process, process.isRunning {
            process.terminate()
        }
        self.process = nil
    }

    private func callTool(
        name: String,
        arguments: [String: Value]
    ) async throws -> String {
        let client = try await connectedClient()
        let request: RequestContext<CallTool.Result> = try await client.callTool(
            name: name,
            arguments: arguments
        )
        let result = try await Self.withTimeout(Self.requestTimeout) {
            try await withTaskCancellationHandler {
                try await request.value
            } onCancel: {
                Task {
                    try? await client.cancelRequest(
                        request.requestID,
                        reason: "Atelier workspace search cancelled"
                    )
                }
            }
        }
        let text = result.content.compactMap { item -> String? in
            guard case .text(let text, _, _) = item else { return nil }
            return text
        }.joined(separator: "\n")
        guard result.isError != true else {
            throw GitNexusMCPError.requestFailed(String(text.prefix(512)))
        }
        guard !text.isEmpty else { throw GitNexusMCPError.invalidResponse }
        return String(text.prefix(Self.maximumResultCharacters))
    }

    private func connectedClient() async throws -> Client {
        if let client, process?.isRunning == true {
            return client
        }
        await stop()
        guard FileManager.default.fileExists(atPath: workspaceRoot.appending(path: ".gitnexus").path) else {
            throw GitNexusMCPError.missingIndex
        }
        let environment = GitProcessEnvironment.configured(
            from: ProcessInfo.processInfo.environment
        )
        guard let command = Self.command(workspaceRoot: workspaceRoot, environment: environment) else {
            throw GitNexusMCPError.unavailable
        }

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.executableURL = command.executableURL
        process.arguments = command.arguments
        process.currentDirectoryURL = workspaceRoot
        process.environment = environment
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw GitNexusMCPError.startupFailed
        }
        try? inputPipe.fileHandleForReading.close()
        try? outputPipe.fileHandleForWriting.close()

        let transport = StdioTransport(
            input: FileDescriptor(rawValue: outputPipe.fileHandleForReading.fileDescriptor),
            output: FileDescriptor(rawValue: inputPipe.fileHandleForWriting.fileDescriptor)
        )
        let client = Client(name: "Atelier", version: "1.0")
        self.process = process
        self.inputPipe = inputPipe
        self.outputPipe = outputPipe
        self.transport = transport
        self.client = client
        do {
            _ = try await Self.withTimeout(Self.requestTimeout) {
                try await withTaskCancellationHandler {
                    try await client.connect(transport: transport)
                } onCancel: {
                    Task { await client.disconnect() }
                }
            }
            let (tools, _) = try await Self.withTimeout(Self.requestTimeout) {
                try await withTaskCancellationHandler {
                    try await client.listTools()
                } onCancel: {
                    Task { await client.disconnect() }
                }
            }
            let names = Set(tools.map(\.name))
            guard names.contains("query"), names.contains("context") else {
                throw GitNexusMCPError.startupFailed
            }
            return client
        } catch {
            await stop()
            if error is CancellationError { throw error }
            if let error = error as? GitNexusMCPError { throw error }
            throw GitNexusMCPError.startupFailed
        }
    }

    private func searchMode() -> String {
        let metaURL = workspaceRoot.appending(path: ".gitnexus/meta.json")
        guard let data = try? Data(contentsOf: metaURL),
              let meta = try? JSONDecoder().decode(GitNexusMeta.self, from: data),
              meta.stats.embeddings > 0,
              meta.capabilities?.vectorSearch?.status == "available" else {
            return "BM25 only; semantic vector search is unavailable."
        }
        return "Hybrid BM25 and vector search ranked by reciprocal rank fusion."
    }

    private nonisolated static func command(
        workspaceRoot: URL,
        environment: [String: String]
    ) -> (executableURL: URL, arguments: [String])? {
        if let executable = executable(named: "gitnexus", environment: environment) {
            return (executable, ["mcp"])
        }
        let runner = workspaceRoot.appending(path: ".gitnexus/run.cjs")
        guard FileManager.default.fileExists(atPath: runner.path),
              let node = executable(named: "node", environment: environment) else {
            return nil
        }
        return (node, [runner.path, "mcp"])
    }

    private nonisolated static func executable(
        named name: String,
        environment: [String: String]
    ) -> URL? {
        for directory in (environment["PATH"] ?? "").split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory), isDirectory: true)
                .appending(path: name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    private nonisolated static func bounded(_ value: String, maximum: Int) -> String {
        String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximum))
    }

    private nonisolated static func withTimeout<Value: Sendable>(
        _ duration: Duration,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try await withThrowingTaskGroup(of: Value.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: duration)
                throw GitNexusMCPError.requestFailed("Timed out.")
            }
            guard let value = try await group.next() else {
                throw GitNexusMCPError.requestFailed("No response.")
            }
            group.cancelAll()
            return value
        }
    }
}

private nonisolated struct GitNexusMeta: Decodable {
    struct Stats: Decodable {
        let embeddings: Int
    }

    struct Capabilities: Decodable {
        struct VectorSearch: Decodable {
            let status: String
        }

        let vectorSearch: VectorSearch?
    }

    let stats: Stats
    let capabilities: Capabilities?
}

nonisolated enum GitNexusResponseParser {
    static func query(
        text: String,
        workspaceRoot: URL,
        searchMode: String
    ) throws -> GitNexusCodeIntelligenceResult {
        let object = try jsonObject(text)
        if let error = object["error"] as? String {
            throw GitNexusMCPError.requestFailed(error)
        }
        let processes = object["processes"] as? [[String: Any]] ?? []
        let processNames = Dictionary(
            uniqueKeysWithValues: processes.compactMap { process -> (String, String)? in
                guard let id = process["id"] as? String,
                      let summary = process["summary"] as? String else {
                    return nil
                }
                return (id, summary)
            }
        )
        var lines = ["GitNexus search mode: \(searchMode)", "Execution flows:"]
        for process in processes.prefix(5) {
            guard let summary = process["summary"] as? String else { continue }
            lines.append("- \(summary)")
        }
        var references: [WorkspaceToolReference] = []
        lines.append("Symbols:")
        for symbol in symbols(from: object["process_symbols"]) {
            guard let reference = reference(
                from: symbol,
                workspaceRoot: workspaceRoot,
                detail: processNames[symbol["process_id"] as? String ?? ""]
            ) else {
                continue
            }
            append(reference, to: &references)
            lines.append("- \(reference.path):\(reference.lineNumber): \(reference.excerpt)")
        }
        for symbol in symbols(from: object["definitions"]) {
            guard let reference = reference(
                from: symbol,
                workspaceRoot: workspaceRoot,
                detail: "definition"
            ) else {
                continue
            }
            append(reference, to: &references)
            lines.append("- \(reference.path):\(reference.lineNumber): \(reference.excerpt)")
        }
        if references.isEmpty {
            lines.append("- No source locations returned.")
        }
        return GitNexusCodeIntelligenceResult(
            content: lines.joined(separator: "\n"),
            references: references
        )
    }

    static func context(
        text: String,
        workspaceRoot: URL
    ) throws -> GitNexusCodeIntelligenceResult {
        let object = try jsonObject(text)
        if let error = object["error"] as? String {
            throw GitNexusMCPError.requestFailed(error)
        }
        var entries: [(symbol: [String: Any], detail: String)] = []
        if let symbol = object["symbol"] as? [String: Any] {
            entries.append((symbol, "selected symbol"))
        }
        for groupName in ["incoming", "outgoing"] {
            guard let groups = object[groupName] as? [String: Any] else { continue }
            for (relation, value) in groups {
                for symbol in symbols(from: value) {
                    entries.append((symbol, "\(groupName) \(relation)"))
                }
            }
        }
        for symbol in symbols(from: object["typed_properties"]) {
            entries.append((symbol, "typed property"))
        }
        for symbol in symbols(from: object["candidates"]) {
            entries.append((symbol, "candidate"))
        }

        var references: [WorkspaceToolReference] = []
        var lines = ["GitNexus symbol context:"]
        for entry in entries {
            guard let reference = reference(
                from: entry.symbol,
                workspaceRoot: workspaceRoot,
                detail: entry.detail
            ) else {
                continue
            }
            append(reference, to: &references)
            lines.append("- \(reference.path):\(reference.lineNumber): \(reference.excerpt)")
        }
        if references.isEmpty {
            lines.append("- No source locations returned.")
        }
        let processes = symbols(from: object["processes"])
        if !processes.isEmpty {
            lines.append("Execution flows:")
            for process in processes.prefix(10) {
                let name = process["name"] as? String ?? process["summary"] as? String
                guard let name, !name.isEmpty else { continue }
                let step = process["step_index"] as? Int
                let stepCount = process["step_count"] as? Int
                if let step, let stepCount {
                    lines.append("- \(name), step \(step + 1) of \(stepCount)")
                } else {
                    lines.append("- \(name)")
                }
            }
        }
        return GitNexusCodeIntelligenceResult(
            content: lines.joined(separator: "\n"),
            references: references
        )
    }

    private static func jsonObject(_ text: String) throws -> [String: Any] {
        guard let start = text.firstIndex(of: "{") else {
            throw GitNexusMCPError.invalidResponse
        }
        var depth = 0
        var isInsideString = false
        var isEscaped = false
        var end: String.Index?
        for index in text.indices[start...] {
            let character = text[index]
            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }
                continue
            }
            if character == "\"" {
                isInsideString = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    end = index
                    break
                }
            }
        }
        guard let end,
              let data = String(text[start...end]).data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GitNexusMCPError.invalidResponse
        }
        return object
    }

    private static func symbols(from value: Any?) -> [[String: Any]] {
        value as? [[String: Any]] ?? []
    }

    private static func reference(
        from symbol: [String: Any],
        workspaceRoot: URL,
        detail: String?
    ) -> WorkspaceToolReference? {
        guard let rawPath = symbol["filePath"] as? String,
              let path = safeRelativePath(rawPath, workspaceRoot: workspaceRoot) else {
            return nil
        }
        let lineNumber = max(1, symbol["startLine"] as? Int ?? 1)
        let name = symbol["name"] as? String ?? URL(fileURLWithPath: path).lastPathComponent
        let kind = symbol["kind"] as? String ?? symbol["type"] as? String
        let uid = symbol["uid"] as? String ?? symbol["id"] as? String
        let parts = [name, kind, detail, uid.map { "UID: \($0)" }]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return WorkspaceToolReference(
            path: path,
            lineNumber: lineNumber,
            excerpt: parts.joined(separator: " - ")
        )
    }

    private static func safeRelativePath(
        _ path: String,
        workspaceRoot: URL
    ) -> String? {
        let candidate = path.hasPrefix("/")
            ? URL(fileURLWithPath: path)
            : workspaceRoot.appending(path: path)
        let resolved = candidate.standardizedFileURL.resolvingSymlinksInPath()
        let rootComponents = workspaceRoot.pathComponents
        let components = resolved.pathComponents
        guard components.starts(with: rootComponents) else { return nil }
        let relative = components.dropFirst(rootComponents.count).joined(separator: "/")
        guard !relative.isEmpty,
              !WorkspaceToolPathPolicy.isSensitive(relativePath: relative) else {
            return nil
        }
        return relative
    }

    private static func append(
        _ reference: WorkspaceToolReference,
        to references: inout [WorkspaceToolReference]
    ) {
        guard references.count < WorkspaceGemmaToolExecutor.maximumSources,
              !references.contains(where: { $0.id == reference.id }) else {
            return
        }
        references.append(reference)
    }
}
