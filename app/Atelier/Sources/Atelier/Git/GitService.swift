import CryptoKit
import Foundation
import Synchronization

enum GitServiceError: LocalizedError {
    case failed(arguments: [String], code: Int32, message: String)
    case outputRead(String)
    case busy(limit: Int)

    var errorDescription: String? {
        switch self {
        case .failed(let arguments, let code, let message):
            return "git \(arguments.joined(separator: " ")) failed (\(code)): \(message)"
        case .outputRead(let message):
            return "Could not read Git output: \(message)"
        case .busy(let limit):
            return "Git command queue is full (limit: \(limit))."
        }
    }
}

nonisolated struct GitCommandQueueSnapshot: Codable, Sendable, Equatable {
    var activeCount = 0
    var queuedCount = 0
    var concurrencyLimit = 0
    var queueCapacity = 0
    var oldestActiveAgeMs = 0.0
}

nonisolated struct GitCommandExecutionState: Sendable {
    private struct Record: Sendable {
        var startedAt: Double?
    }

    private var records: [UUID: Record] = [:]
    let capacity: Int
    let concurrencyLimit: Int

    init(capacity: Int, concurrencyLimit: Int) {
        self.capacity = capacity
        self.concurrencyLimit = concurrencyLimit
    }

    mutating func enqueue(_ id: UUID) -> Bool {
        guard records.count < capacity else { return false }
        records[id] = Record()
        return true
    }

    mutating func begin(_ id: UUID, at time: Double) -> Bool {
        guard records[id] != nil else { return false }
        records[id]?.startedAt = time
        return true
    }

    mutating func remove(_ id: UUID) {
        records[id] = nil
    }

    func snapshot(at time: Double) -> GitCommandQueueSnapshot {
        let starts = records.values.compactMap(\.startedAt)
        return GitCommandQueueSnapshot(
            activeCount: starts.count,
            queuedCount: records.count - starts.count,
            concurrencyLimit: concurrencyLimit,
            queueCapacity: capacity,
            oldestActiveAgeMs: starts.min().map { max(0, time - $0) * 1_000 } ?? 0
        )
    }
}

private nonisolated struct GitCommandCompletionState {
    var continuation: CheckedContinuation<Data, Error>?
    var result: Result<Data, Error>?
}

private nonisolated final class GitCommandCompletion: @unchecked Sendable {
    private let state = Mutex(GitCommandCompletionState())

    var isFinished: Bool {
        state.withLock { $0.result != nil }
    }

    func install(_ continuation: CheckedContinuation<Data, Error>) {
        let result = state.withLock { state -> Result<Data, Error>? in
            if let result = state.result { return result }
            state.continuation = continuation
            return nil
        }
        if let result { continuation.resume(with: result) }
    }

    func finish(_ result: Result<Data, Error>) {
        let continuation = state.withLock { state -> CheckedContinuation<Data, Error>? in
            guard state.result == nil else { return nil }
            state.result = result
            defer { state.continuation = nil }
            return state.continuation
        }
        continuation?.resume(with: result)
    }
}

nonisolated final class GitCommandExecutor: @unchecked Sendable {
    static let shared = GitCommandExecutor()
    static let concurrencyLimit = 4
    static let queueCapacity = 64

    private let operations: OperationQueue
    private let clock: RuntimeMonotonicClock
    private let state = Mutex(GitCommandExecutionState(
        capacity: queueCapacity,
        concurrencyLimit: concurrencyLimit
    ))

    init(clock: RuntimeMonotonicClock = SystemRuntimeMonotonicClock()) {
        self.clock = clock
        operations = OperationQueue()
        operations.name = "app.atelier.git-commands"
        operations.qualityOfService = .userInitiated
        operations.maxConcurrentOperationCount = Self.concurrencyLimit
    }

    func execute(
        arguments: [String],
        workspacePath: String,
        maxOutputBytes: Int?,
        allowedExitCodes: Set<Int32>
    ) async throws -> Data {
        let id = UUID()
        let command = GitCommand()
        let completion = GitCommandCompletion()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                completion.install(continuation)
                guard !completion.isFinished else { return }
                guard state.withLock({ $0.enqueue(id) }) else {
                    completion.finish(.failure(GitServiceError.busy(limit: Self.queueCapacity)))
                    return
                }
                operations.addOperation { [self] in
                    guard state.withLock({ $0.begin(id, at: clock.now()) }) else { return }
                    defer { state.withLock { $0.remove(id) } }
                    do {
                        completion.finish(.success(try command.run(
                            arguments: arguments,
                            workspacePath: workspacePath,
                            maxOutputBytes: maxOutputBytes,
                            allowedExitCodes: allowedExitCodes
                        )))
                    } catch {
                        completion.finish(.failure(error))
                    }
                }
            }
        } onCancel: {
            command.cancel()
            state.withLock { $0.remove(id) }
            completion.finish(.failure(CancellationError()))
        }
    }

    func snapshot() -> GitCommandQueueSnapshot {
        state.withLock { $0.snapshot(at: clock.now()) }
    }
}

nonisolated struct GitSnapshot: Equatable, Sendable {
    let status: GitStatus
    let branch: String
    let branches: [String]
}

nonisolated struct GitCommit: Identifiable, Equatable, Sendable {
    let hash: String
    let shortHash: String
    let author: String
    let authorEmail: String
    let date: Date
    let subject: String

    var id: String { hash }

    var authorAvatarURL: URL? {
        let email = authorEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !email.isEmpty else { return nil }

        if email.hasSuffix("@users.noreply.github.com"),
           let localPart = email.split(separator: "@", maxSplits: 1).first {
            let username = localPart.split(separator: "+").last.map(String.init) ?? ""
            if !username.isEmpty {
                return URL(string: "https://github.com/\(username).png?size=96")
            }
        }

        let digest = Insecure.MD5.hash(data: Data(email.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return URL(string: "https://www.gravatar.com/avatar/\(digest)?d=404&s=96")
    }
}

nonisolated enum GitCommitLogParser {
    private static let recordSeparator: Character = "\u{001E}"
    private static let fieldSeparator: Character = "\u{001F}"

    static func parse(_ data: Data) -> [GitCommit] {
        String(decoding: data, as: UTF8.self)
            .split(separator: recordSeparator, omittingEmptySubsequences: true)
            .compactMap { record in
                let fields = record.split(
                    separator: fieldSeparator,
                    maxSplits: 5,
                    omittingEmptySubsequences: false
                )
                guard fields.count == 6, let timestamp = Double(fields[4]) else { return nil }
                return GitCommit(
                    hash: String(fields[0]),
                    shortHash: String(fields[1]),
                    author: String(fields[2]),
                    authorEmail: String(fields[3]),
                    date: Date(timeIntervalSince1970: timestamp),
                    subject: String(fields[5]).trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
    }
}

private nonisolated struct GitOutputState: Sendable {
    var value = Data()
    var wasTruncated = false
    var readError: String?
}

private nonisolated final class GitOutputBox: Sendable {
    private let state = Mutex(GitOutputState())

    func capture(_ fileHandle: FileHandle, limit: Int?) {
        var captured = Data()
        var truncated = false
        var readError: String?
        do {
            while let chunk = try fileHandle.read(upToCount: 65_536), !chunk.isEmpty {
                if let limit {
                    let remaining = max(0, limit - captured.count)
                    captured.append(chunk.prefix(remaining))
                    if chunk.count > remaining { truncated = true }
                } else {
                    captured.append(chunk)
                }
            }
        } catch {
            readError = error.localizedDescription
        }
        state.withLock {
            $0.value = captured
            $0.wasTruncated = truncated
            $0.readError = readError
        }
    }

    func get() -> (data: Data, truncated: Bool, readError: String?) {
        state.withLock { ($0.value, $0.wasTruncated, $0.readError) }
    }
}

private nonisolated struct GitCommandState {
    var process: Process?
    var isCancelled = false
}

nonisolated enum GitProcessEnvironment {
    private static let standardToolDirectories = [
        "/opt/homebrew/bin",
        "/usr/local/bin"
    ]

    static func configured(from base: [String: String]) -> [String: String] {
        var environment = base
        var paths = (base["PATH"] ?? "")
            .split(separator: ":", omittingEmptySubsequences: true)
            .map(String.init)
        var toolDirectories = standardToolDirectories
        if let home = base["HOME"], !home.isEmpty {
            toolDirectories.append("\(home)/.local/bin")
        }
        for directory in toolDirectories where !paths.contains(directory) {
            paths.append(directory)
        }
        environment["PATH"] = paths.joined(separator: ":")
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        return environment
    }
}

nonisolated final class GitCommand: Sendable {
    private let state = Mutex(GitCommandState())

    func run(
        arguments: [String],
        workspacePath: String,
        maxOutputBytes: Int? = nil,
        allowedExitCodes: Set<Int32> = [0]
    ) throws -> Data {
        let process = Process()
        let output = Pipe()
        let errorOutput = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: workspacePath, isDirectory: true)
        process.environment = GitProcessEnvironment.configured(
            from: ProcessInfo.processInfo.environment
        )
        process.standardOutput = output
        process.standardError = errorOutput

        let shouldCancel = state.withLock {
            $0.process = process
            return $0.isCancelled
        }

        if shouldCancel {
            clear(process)
            throw CancellationError()
        }

        do {
            try process.run()
        } catch {
            clear(process)
            throw error
        }
        let cancelledAfterLaunch = state.withLock { $0.isCancelled }
        if cancelledAfterLaunch { process.terminate() }

        let outputBox = GitOutputBox()
        let errorBox = GitOutputBox()
        let readers = DispatchGroup()
        readers.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            outputBox.capture(output.fileHandleForReading, limit: maxOutputBytes)
            readers.leave()
        }
        readers.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            errorBox.capture(errorOutput.fileHandleForReading, limit: 1_000_000)
            readers.leave()
        }
        process.waitUntilExit()
        readers.wait()
        clear(process)

        let outputResult = outputBox.get()
        let errorResult = errorBox.get()
        if let readError = outputResult.readError ?? errorResult.readError {
            throw GitServiceError.outputRead(readError)
        }
        let errorData = errorResult.data
        guard allowedExitCodes.contains(process.terminationStatus) else {
            throw GitServiceError.failed(
                arguments: arguments,
                code: process.terminationStatus,
                message: String(decoding: errorData, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        if outputResult.truncated {
            var data = outputResult.data
            data.append(Data("\n\n... diff output truncated at \(maxOutputBytes ?? 0) bytes ...\n".utf8))
            return data
        }
        return outputResult.data
    }

    func cancel() {
        let process = state.withLock {
            $0.isCancelled = true
            return $0.process
        }
        if process?.isRunning == true {
            process?.terminate()
        }
    }

    private func clear(_ process: Process) {
        state.withLock {
            if $0.process === process { $0.process = nil }
        }
    }
}

nonisolated final class GitService: Sendable {
    func snapshot(workspacePath: String) async throws -> GitSnapshot {
        async let statusData = run(
            arguments: ["status", "--ignored=matching", "--porcelain=v2", "-z"],
            workspacePath: workspacePath
        )
        async let branchData = run(
            arguments: ["branch", "--show-current"],
            workspacePath: workspacePath
        )
        async let branchesData = run(
            arguments: ["branch", "--format=%(refname:short)"],
            workspacePath: workspacePath
        )
        let (statusOutput, branchOutput, branchesOutput) = try await (
            statusData,
            branchData,
            branchesData
        )
        return GitSnapshot(
            status: GitStatus.parse(statusOutput),
            branch: String(decoding: branchOutput, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            branches: String(decoding: branchesOutput, as: UTF8.self)
                .split(whereSeparator: \Character.isNewline)
                .map(String.init)
        )
    }

    /// Working-tree status only. Filesystem-driven refreshes use this so a burst
    /// of file edits spawns one `git status` instead of the three subprocesses a
    /// full snapshot needs; branch and branch-list refresh stay on git actions.
    func status(workspacePath: String) async throws -> GitStatus {
        let data = try await run(
            arguments: ["status", "--ignored=matching", "--porcelain=v2", "-z"],
            workspacePath: workspacePath
        )
        return GitStatus.parse(data)
    }

    func recentCommits(workspacePath: String, limit: Int = 20) async throws -> [GitCommit] {
        let boundedLimit = min(max(limit, 1), 100)
        let data = try await run(
            arguments: [
                "log",
                "--max-count=\(boundedLimit)",
                "--pretty=format:%H%x1f%h%x1f%an%x1f%ae%x1f%at%x1f%s%x1e"
            ],
            workspacePath: workspacePath,
            maxOutputBytes: 256_000,
            allowedExitCodes: [0, 128]
        )
        return GitCommitLogParser.parse(data)
    }

    func diff(
        path: String,
        originalPath: String?,
        staged: Bool,
        workspacePath: String
    ) async throws -> String {
        var arguments = ["diff"]
        if staged { arguments.append("--cached") }
        arguments.append(contentsOf: ["--no-color", "--no-ext-diff", "--"])
        if let originalPath { arguments.append(originalPath) }
        arguments.append(path)
        let data = try await run(
            arguments: arguments,
            workspacePath: workspacePath,
            maxOutputBytes: 4_000_000
        )
        return String(decoding: data, as: UTF8.self)
    }

    func untrackedDiff(path: String, workspacePath: String) async throws -> String {
        // git diff --no-index compares the file against /dev/null, so an
        // untracked file renders as an all-additions unified diff. It exits
        // with code 1 whenever the two inputs differ, which is expected here.
        let data = try await run(
            arguments: [
                "diff", "--no-color", "--no-ext-diff", "--no-index", "--", "/dev/null", path
            ],
            workspacePath: workspacePath,
            maxOutputBytes: 4_000_000,
            allowedExitCodes: [0, 1]
        )
        return String(decoding: data, as: UTF8.self)
    }

    func run(
        arguments: [String],
        workspacePath: String,
        maxOutputBytes: Int? = nil,
        allowedExitCodes: Set<Int32> = [0]
    ) async throws -> Data {
        try await GitCommandExecutor.shared.execute(
            arguments: arguments,
            workspacePath: workspacePath,
            maxOutputBytes: maxOutputBytes,
            allowedExitCodes: allowedExitCodes
        )
    }

    func stage(path: String, workspacePath: String) async throws {
        _ = try await run(arguments: ["add", "--", path], workspacePath: workspacePath)
    }

    func stageAll(workspacePath: String) async throws {
        _ = try await run(arguments: ["add", "-A"], workspacePath: workspacePath)
    }

    func unstage(path: String, originalPath: String?, workspacePath: String) async throws {
        var paths = [path]
        if let originalPath, originalPath != path {
            paths.append(originalPath)
        }

        if try await hasHead(workspacePath: workspacePath) {
            _ = try await run(
                arguments: ["restore", "--staged", "--"] + paths,
                workspacePath: workspacePath
            )
        } else {
            _ = try await run(
                arguments: ["rm", "--cached", "-f", "--"] + paths,
                workspacePath: workspacePath
            )
        }
    }

    func discard(path: String, workspacePath: String) async throws {
        _ = try await run(arguments: ["restore", "--", path], workspacePath: workspacePath)
    }

    func commit(message: String, workspacePath: String) async throws {
        _ = try await run(
            arguments: ["commit", "-m", message],
            workspacePath: workspacePath
        )
    }

    func push(workspacePath: String) async throws {
        _ = try await run(arguments: ["push"], workspacePath: workspacePath)
    }

    func switchBranch(_ branch: String, workspacePath: String) async throws {
        _ = try await run(arguments: ["checkout", branch], workspacePath: workspacePath)
    }

    private func hasHead(workspacePath: String) async throws -> Bool {
        do {
            _ = try await run(
                arguments: ["rev-parse", "--verify", "HEAD"],
                workspacePath: workspacePath
            )
            return true
        } catch GitServiceError.failed(_, let code, _) where code == 128 {
            return false
        }
    }
}
