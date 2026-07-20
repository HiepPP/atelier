import Foundation
import Testing
@testable import Atelier

@Suite("Workspace read-only tools")
struct WorkspaceToolExecutorTests {
    @Test("Reads bounded lines and searches workspace text")
    func readAndSearch() async throws {
        let root = try fixture()
        let executor = WorkspaceToolExecutor(workspaceRoot: root)
        let read = try await executor.execute(
            call(.readFile, [
                "path": .string("Sources/main.swift"),
                "start_line": .number(2),
                "line_count": .number(2)
            ])
        )
        #expect(read.content.contains("2: let needle = 1"))
        #expect(!read.content.contains("4: end"))
        #expect(read.truncated)

        let search = try await executor.execute(
            call(.searchWorkspace, ["query": .string("needle")])
        )
        #expect(search.content.contains("Sources/main.swift:2"))
    }

    @Test("Rejects traversal, symlink escapes, sensitive files, and unknown tools")
    func rejectsUnsafeRequests() async throws {
        let root = try fixture()
        let outside = root.deletingLastPathComponent().appendingPathComponent("outside-\(UUID().uuidString).txt")
        try Data("secret outside".utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("escape.txt"),
            withDestinationURL: outside
        )
        let executor = WorkspaceToolExecutor(workspaceRoot: root)

        await #expect(throws: WorkspaceToolError.outsideWorkspace) {
            try await executor.execute(call(.readFile, ["path": .string("../outside.txt")]))
        }
        await #expect(throws: WorkspaceToolError.outsideWorkspace) {
            try await executor.execute(call(.readFile, ["path": .string("escape.txt")]))
        }
        await #expect(throws: WorkspaceToolError.sensitivePath) {
            try await executor.execute(call(.readFile, ["path": .string(".env")]))
        }
        let unknown = OllamaToolCall(
            function: OllamaFunctionCall(name: "write_file", arguments: [:])
        )
        await #expect(throws: WorkspaceToolError.unknownTool("write_file")) {
            try await executor.execute(unknown)
        }
    }

    @Test("Reads a bounded Git diff")
    func gitDiff() async throws {
        let root = try fixture()
        let git = GitService()
        _ = try await git.run(arguments: ["init", "-q"], workspacePath: root.path)
        _ = try await git.run(arguments: ["add", "."], workspacePath: root.path)
        _ = try await git.run(
            arguments: ["-c", "user.name=Atelier", "-c", "user.email=test@atelier.local", "commit", "-qm", "fixture"],
            workspacePath: root.path
        )
        try Data("changed needle\n".utf8).write(to: root.appendingPathComponent("Sources/main.swift"))
        let executor = WorkspaceToolExecutor(workspaceRoot: root)

        let result = try await executor.execute(call(.readGitDiff, [:]))
        #expect(result.content.contains("changed needle"))
    }

    @Test("In-flight search stops when its owner is cancelled")
    func cancellation() async throws {
        let root = try fixture()
        for index in 0..<500 {
            try Data(repeating: 65, count: 20_000).write(
                to: root.appendingPathComponent("Sources/file-\(index).txt")
            )
        }
        let executor = WorkspaceToolExecutor(workspaceRoot: root)
        let task = Task {
            try await executor.execute(call(.searchWorkspace, ["query": .string("missing")]))
        }
        let canceller = Task {
            try? await Task.sleep(for: .milliseconds(5))
            task.cancel()
        }
        await #expect(throws: WorkspaceToolError.cancelled) { try await task.value }
        await canceller.value
    }

    @Test("Terminal output caps lines and characters and errors without a terminal")
    func terminalOutput() async throws {
        let root = try fixture()

        // No provider: no terminal is selected.
        let bare = WorkspaceToolExecutor(workspaceRoot: root)
        await #expect(throws: WorkspaceToolError.noTerminalSelected) {
            try await bare.execute(call(.readTerminalOutput, [:]))
        }

        // Provider returning nil: still no terminal selected.
        let emptySpy = TerminalSnapshotSpy(output: nil)
        let emptyExecutor = WorkspaceToolExecutor(
            workspaceRoot: root,
            terminalSnapshot: { lines in emptySpy.snapshot(lines) }
        )
        await #expect(throws: WorkspaceToolError.noTerminalSelected) {
            try await emptyExecutor.execute(call(.readTerminalOutput, [:]))
        }

        // Default line count is 200; a large request is capped at 400.
        let capSpy = TerminalSnapshotSpy(output: "line")
        let capExecutor = WorkspaceToolExecutor(
            workspaceRoot: root,
            terminalSnapshot: { lines in capSpy.snapshot(lines) }
        )
        _ = try await capExecutor.execute(call(.readTerminalOutput, [:]))
        #expect(capSpy.requestedLines == 200)
        _ = try await capExecutor.execute(call(.readTerminalOutput, ["lines": .number(9_999)]))
        #expect(capSpy.requestedLines == 400)

        // Characters beyond the cap are truncated.
        let big = String(repeating: "x", count: 150_000)
        let bigSpy = TerminalSnapshotSpy(output: big)
        let bigExecutor = WorkspaceToolExecutor(
            workspaceRoot: root,
            terminalSnapshot: { lines in bigSpy.snapshot(lines) }
        )
        let result = try await bigExecutor.execute(call(.readTerminalOutput, ["lines": .number(400)]))
        #expect(result.truncated)
        #expect(result.content.count <= 100_000)
    }

    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("atelier-tools-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Sources"),
            withIntermediateDirectories: true
        )
        try Data("start\nlet needle = 1\nmore\nend".utf8).write(
            to: root.appendingPathComponent("Sources/main.swift")
        )
        try Data("do not return".utf8).write(to: root.appendingPathComponent(".env"))
        return root
    }

    private func call(
        _ name: WorkspaceToolName,
        _ arguments: [String: OllamaJSONValue]
    ) -> OllamaToolCall {
        OllamaToolCall(function: OllamaFunctionCall(name: name.rawValue, arguments: arguments))
    }
}

@MainActor
final class TerminalSnapshotSpy {
    private(set) var requestedLines: Int?
    let output: String?

    init(output: String?) {
        self.output = output
    }

    func snapshot(_ lines: Int) -> String? {
        requestedLines = lines
        return output
    }
}
