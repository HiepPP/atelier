import Foundation
import Synchronization

enum GitServiceError: LocalizedError {
    case failed(arguments: [String], code: Int32, message: String)
    case outputRead(String)

    var errorDescription: String? {
        switch self {
        case .failed(let arguments, let code, let message):
            return "git \(arguments.joined(separator: " ")) failed (\(code)): \(message)"
        case .outputRead(let message):
            return "Could not read Git output: \(message)"
        }
    }
}

nonisolated struct GitSnapshot: Equatable, Sendable {
    let status: GitStatus
    let branch: String
    let branches: [String]
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

nonisolated final class GitCommand: Sendable {
    private let state = Mutex(GitCommandState())

    func run(
        arguments: [String],
        workspacePath: String,
        maxOutputBytes: Int? = nil
    ) throws -> Data {
        let process = Process()
        let output = Pipe()
        let errorOutput = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: workspacePath, isDirectory: true)
        process.standardOutput = output
        process.standardError = errorOutput

        let shouldCancel = state.withLock {
            $0.process = process
            return $0.isCancelled
        }

        do {
            try process.run()
        } catch {
            clear(process)
            throw error
        }
        let cancelledAfterLaunch = state.withLock { $0.isCancelled }
        if shouldCancel || cancelledAfterLaunch { process.terminate() }

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
        guard process.terminationStatus == 0 else {
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

    func run(
        arguments: [String],
        workspacePath: String,
        maxOutputBytes: Int? = nil
    ) async throws -> Data {
        let command = GitCommand()
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) {
                try command.run(
                    arguments: arguments,
                    workspacePath: workspacePath,
                    maxOutputBytes: maxOutputBytes
                )
            }.value
        } onCancel: {
            command.cancel()
        }
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
