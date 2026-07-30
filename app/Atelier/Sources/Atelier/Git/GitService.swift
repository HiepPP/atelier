import CryptoKit
import Darwin
import Foundation
import Synchronization

enum GitServiceError: LocalizedError {
    case failed(arguments: [String], code: Int32, message: String)
    case outputRead(String)
    case busy(limit: Int)
    case timedOut(arguments: [String], seconds: Double)

    var errorDescription: String? {
        switch self {
        case .failed(let arguments, let code, let message):
            return "git \(arguments.joined(separator: " ")) failed (\(code)): \(message)"
        case .outputRead(let message):
            return "Could not read Git output: \(message)"
        case .busy(let limit):
            return "Git command queue is full (limit: \(limit))."
        case .timedOut(let arguments, let seconds):
            return "git \(arguments.joined(separator: " ")) timed out after "
                + "\(String(format: "%g", seconds))s and was terminated."
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
    /// Commits on HEAD that the upstream does not have. Zero when the branch
    /// has no upstream, so a missing remote never reads as pending work.
    let ahead: Int
    /// Commits on the upstream that HEAD does not have. Only as fresh as the
    /// last external fetch: Atelier never fetches on its own.
    let behind: Int

    init(
        status: GitStatus,
        branch: String,
        branches: [String],
        ahead: Int = 0,
        behind: Int = 0
    ) {
        self.status = status
        self.branch = branch
        self.branches = branches
        self.ahead = ahead
        self.behind = behind
    }
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

/// Parses `git rev-list --left-right --count <upstream>...HEAD`, which prints
/// one `behind<TAB>ahead` record. A branch with no upstream fails with exit 128
/// and empty output, so anything unparsable reads as zero rather than an error.
nonisolated enum GitUpstreamCounts {
    static func parse(_ data: Data) -> (ahead: Int, behind: Int) {
        let fields = String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \Character.isWhitespace)
        guard
            fields.count == 2,
            let behind = Int(fields[0]),
            let ahead = Int(fields[1]),
            behind >= 0,
            ahead >= 0
        else {
            return (ahead: 0, behind: 0)
        }
        return (ahead: ahead, behind: behind)
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
    var didTimeOut = false
}

/// Deadline policy for git subprocesses. A wedged network command (stalled
/// SSH during push or fetch) must not hold an executor slot forever: four
/// wedged commands saturate `GitCommandExecutor` and disable every git
/// feature until app restart.
nonisolated enum GitCommandTimeoutPolicy {
    static let longRunningDeadline: Duration = .seconds(120)
    static let standardDeadline: Duration = .seconds(30)
    static let killEscalationGrace: Duration = .seconds(5)

    private static let longRunningSubcommands: Set<String> = ["push", "fetch", "pull", "clone"]
    private static let globalOptionsWithValue: Set<String> = [
        "-c", "-C", "--git-dir", "--work-tree"
    ]

    static func deadline(for arguments: [String]) -> Duration {
        guard let subcommand = subcommand(in: arguments) else { return standardDeadline }
        return longRunningSubcommands.contains(subcommand) ? longRunningDeadline : standardDeadline
    }

    /// First argument that is neither a global option nor a global option's value.
    static func subcommand(in arguments: [String]) -> String? {
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if globalOptionsWithValue.contains(argument) {
                index += 2
            } else if argument.hasPrefix("-") {
                index += 1
            } else {
                return argument
            }
        }
        return nil
    }

    static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds)
            + Double(duration.components.attoseconds) / 1e18
    }
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
        // No controlling terminal exists to answer credential prompts; a
        // prompting command must fail fast instead of hanging to its deadline.
        environment["GIT_TERMINAL_PROMPT"] = "0"
        return environment
    }
}

nonisolated final class GitCommand: Sendable {
    private let state = Mutex(GitCommandState())

    func run(
        arguments: [String],
        workspacePath: String,
        maxOutputBytes: Int? = nil,
        allowedExitCodes: Set<Int32> = [0],
        deadline: Duration? = nil
    ) throws -> Data {
        let process = Process()
        let output = Pipe()
        let errorOutput = Pipe()
        // Foundation pipes are inheritable. A concurrent child process can keep
        // another Git command's writer alive and prevent its readers from seeing EOF.
        for fileHandle in [
            output.fileHandleForReading,
            output.fileHandleForWriting,
            errorOutput.fileHandleForReading,
            errorOutput.fileHandleForWriting
        ] {
            let descriptor = fileHandle.fileDescriptor
            let flags = fcntl(descriptor, F_GETFD)
            guard flags >= 0,
                  fcntl(descriptor, F_SETFD, flags | FD_CLOEXEC) >= 0 else {
                throw GitServiceError.outputRead(
                    "Could not configure Git output pipe: \(String(cString: strerror(errno)))"
                )
            }
        }
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

        // Deadline enforcement: terminate a wedged command instead of holding
        // an executor slot forever. Both work items re-check the state-held
        // process identity, so a normally exited command is never signalled.
        let deadlineSeconds = GitCommandTimeoutPolicy.seconds(
            deadline ?? GitCommandTimeoutPolicy.deadline(for: arguments)
        )
        let terminateOnDeadline = DispatchWorkItem { [self] in
            let running = state.withLock { state -> Process? in
                guard let process = state.process, process.isRunning else { return nil }
                state.didTimeOut = true
                return process
            }
            running?.terminate()
        }
        // git can catch SIGTERM while blocked on a hung transport; escalate.
        let killAfterGrace = DispatchWorkItem { [self] in
            let running = state.withLock { state -> Process? in
                guard let process = state.process, process.isRunning else { return nil }
                return process
            }
            if let running { kill(running.processIdentifier, SIGKILL) }
        }
        let timerQueue = DispatchQueue.global(qos: .utility)
        timerQueue.asyncAfter(deadline: .now() + deadlineSeconds, execute: terminateOnDeadline)
        timerQueue.asyncAfter(
            deadline: .now() + deadlineSeconds
                + GitCommandTimeoutPolicy.seconds(GitCommandTimeoutPolicy.killEscalationGrace),
            execute: killAfterGrace
        )

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
        terminateOnDeadline.cancel()
        killAfterGrace.cancel()
        let didTimeOut = state.withLock { $0.didTimeOut }
        if didTimeOut {
            // A grandchild (ssh, credential helper) can inherit the pipe write
            // ends and keep them open past the git process's death; bound the
            // reader wait so a timed-out command frees its executor slot.
            _ = readers.wait(timeout: .now() + 2)
        } else {
            readers.wait()
        }
        clear(process)

        let outputResult = outputBox.get()
        let errorResult = errorBox.get()
        if didTimeOut, !allowedExitCodes.contains(process.terminationStatus) {
            throw GitServiceError.timedOut(arguments: arguments, seconds: deadlineSeconds)
        }
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

// Every entry point is `@concurrent`: the package enables
// `NonisolatedNonsendingByDefault`, so a plain `nonisolated async func` runs in
// the caller's isolation. Called from `@MainActor` models, that put every status,
// history, and diff parse on the main thread.
nonisolated final class GitService: Sendable {
    @concurrent
    func snapshot(workspacePath: String) async throws -> GitSnapshot {
        async let statusData = run(
            arguments: [
                "status",
                "--ignored=matching",
                "--untracked-files=all",
                "--porcelain=v2",
                "-z"
            ],
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
        async let upstreamCounts = upstreamCounts(workspacePath: workspacePath)
        let (statusOutput, branchOutput, branchesOutput, counts) = try await (
            statusData,
            branchData,
            branchesData,
            upstreamCounts
        )
        return GitSnapshot(
            status: GitStatus.parse(statusOutput),
            branch: String(decoding: branchOutput, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            branches: String(decoding: branchesOutput, as: UTF8.self)
                .split(whereSeparator: \Character.isNewline)
                .map(String.init),
            ahead: counts.ahead,
            behind: counts.behind
        )
    }

    /// Ahead/behind against the branch upstream. A missing upstream, a fresh
    /// repository with no HEAD, and any other failure all read as zero: sync
    /// counts are informational, so they must never fail the whole snapshot.
    @concurrent
    func upstreamCounts(workspacePath: String) async -> (ahead: Int, behind: Int) {
        do {
            let data = try await run(
                arguments: ["rev-list", "--left-right", "--count", "@{upstream}...HEAD"],
                workspacePath: workspacePath,
                allowedExitCodes: [0, 128]
            )
            return GitUpstreamCounts.parse(data)
        } catch {
            return (ahead: 0, behind: 0)
        }
    }

    /// Working-tree status only. Filesystem-driven refreshes use this so a burst
    /// of file edits spawns one `git status` instead of the four subprocesses a
    /// full snapshot needs; branch, branch list, and upstream counts refresh
    /// stay on git actions.
    @concurrent
    func status(workspacePath: String) async throws -> GitStatus {
        let data = try await run(
            arguments: [
                "status",
                "--ignored=matching",
                "--untracked-files=all",
                "--porcelain=v2",
                "-z"
            ],
            workspacePath: workspacePath
        )
        return GitStatus.parse(data)
    }

    @concurrent
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

    @concurrent
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

    @concurrent
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

    @concurrent
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

    func discard(changes: [GitChange], workspacePath: String) async throws {
        let trackedPaths = changes
            .filter { $0.kind != .untracked }
            .map(\.path)
        if !trackedPaths.isEmpty {
            _ = try await run(
                arguments: ["restore", "--"] + trackedPaths,
                workspacePath: workspacePath
            )
        }

        let workspaceURL = URL(fileURLWithPath: workspacePath, isDirectory: true)
        for change in changes where change.kind == .untracked {
            let url = workspaceURL.appendingPathComponent(change.path).standardizedFileURL
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
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

    /// Updates the remote-tracking refs the ahead/behind counts read from.
    /// Only explicit refreshes call this: a fetch is a network round trip.
    func fetch(workspacePath: String) async throws {
        _ = try await run(arguments: ["fetch", "--quiet"], workspacePath: workspacePath)
    }

    /// Fast-forward only. A diverged branch fails here with git's own message
    /// instead of silently creating a merge commit from a one-click control.
    func pull(workspacePath: String) async throws {
        _ = try await run(arguments: ["pull", "--ff-only"], workspacePath: workspacePath)
    }

    func switchBranch(_ branch: String, workspacePath: String) async throws {
        _ = try await run(arguments: ["checkout", branch], workspacePath: workspacePath)
    }

    /// Every local branch, remote branch, and tag with the commit metadata the
    /// branch picker shows. Sorted newest first inside each section by git, so
    /// the picker never re-sorts.
    @concurrent
    func refs(workspacePath: String) async throws -> [GitRef] {
        let data = try await run(
            arguments: [
                "for-each-ref",
                "--sort=-committerdate",
                "--format=\(GitRefParser.format)",
                "refs/heads", "refs/remotes", "refs/tags"
            ],
            workspacePath: workspacePath,
            maxOutputBytes: 512_000,
            allowedExitCodes: [0, 128]
        )
        return GitRefParser.parse(data)
    }

    func createBranch(
        _ name: String,
        from base: String?,
        workspacePath: String
    ) async throws {
        var arguments = ["checkout", "-b", name]
        if let base, !base.isEmpty {
            arguments.append(base)
        }
        _ = try await run(arguments: arguments, workspacePath: workspacePath)
    }

    /// Checks out a remote branch as a local branch that tracks it, matching
    /// what `git checkout <name>` does when the name is unambiguous.
    func checkoutTracking(_ remoteRef: String, as localName: String, workspacePath: String) async throws {
        _ = try await run(
            arguments: ["checkout", "-b", localName, "--track", remoteRef],
            workspacePath: workspacePath
        )
    }

    func checkoutDetached(_ ref: String, workspacePath: String) async throws {
        _ = try await run(
            arguments: ["checkout", "--detach", ref],
            workspacePath: workspacePath
        )
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
