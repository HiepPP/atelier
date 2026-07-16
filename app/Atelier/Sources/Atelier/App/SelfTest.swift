import Dispatch
import Foundation

enum SelfTest {
    static func run() -> Never {
        Task { @MainActor in
            let passed = await execute()
            print(passed ? "\nSELFTEST: ALL PASS" : "\nSELFTEST: SOME FAIL")
            exit(passed ? 0 : 1)
        }
        dispatchMain()
    }

    @MainActor
    private static func execute() async -> Bool {
        var passed = true
        func check(_ name: String, _ condition: Bool, _ detail: String) {
            print("[\(condition ? "PASS" : "FAIL")] \(name): \(detail)")
            if !condition { passed = false }
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "atelier-selftest-\(ProcessInfo.processInfo.processIdentifier)",
                isDirectory: true
            )
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

            let persistenceURL = root.appendingPathComponent("state.json")
            let workspaceState = WorkspaceState(
                path: root.path,
                bookmark: nil,
                lastOpenedAt: Date(timeIntervalSince1970: 1)
            )
            let persistence = WorkspacePersistenceService(fileURL: persistenceURL)
            try await persistence.save(workspaceState)
            let loadedState = try await persistence.load()
            check("workspace persistence", loadedState == workspaceState, "state round-tripped")

            let textURL = root.appendingPathComponent("text.txt")
            let binaryURL = root.appendingPathComponent("binary.bin")
            let largeURL = root.appendingPathComponent("large.txt")
            let savedURL = root.appendingPathComponent("saved.txt")
            try Data("hello".utf8).write(to: textURL)
            try Data([0x41, 0x00, 0x42]).write(to: binaryURL)
            try Data(repeating: 0x41, count: 9).write(to: largeURL)

            check("FileLoader text", FileLoader.load(url: textURL) == .text("hello"), "text decoded")
            check("FileLoader binary", FileLoader.load(url: binaryURL) == .binary, "null byte detected")
            check(
                "FileLoader tooLarge",
                FileLoader.load(url: largeURL, limit: 8) == .tooLarge(9),
                "size capped"
            )
            check(
                "FileLoader async",
                await FileLoader.loadAsync(url: textURL) == .text("hello"),
                "background load decoded text"
            )

            try await FileSaver.saveAsync(text: "saved content", url: savedURL)
            let savedText = try String(contentsOf: savedURL, encoding: .utf8)
            check("FileSaver async", savedText == "saved content", "background save wrote content")

            check(
                "FileViewer highlight small",
                FileHighlightPolicy.usesSyntaxHighlighting(
                    byteCount: FileHighlightPolicy.maximumHighlightedBytes
                ),
                "threshold content keeps syntax colors"
            )
            check(
                "FileViewer fallback large",
                !FileHighlightPolicy.usesSyntaxHighlighting(
                    byteCount: FileHighlightPolicy.maximumHighlightedBytes + 1
                ),
                "large content uses plain native text"
            )

            verifyGitParsing(check: check)
            await verifyGitOperations(root: root, check: check)
        } catch {
            check("self-test setup", false, error.localizedDescription)
        }
        return passed
    }

    @MainActor
    private static func verifyGitParsing(
        check: (_ name: String, _ condition: Bool, _ detail: String) -> Void
    ) {
        let statusSample = [
            "1 M. N... 100644 100644 100644 abcdef1 abcdef2 staged.txt",
            "1 .M N... 100644 100644 100644 abcdef1 abcdef1 unstaged.txt",
            "? new file.txt",
            ""
        ].joined(separator: "\0")
        let status = GitStatus.parse(Data(statusSample.utf8))
        check("GitStatus staged", status.staged.map(\.path) == ["staged.txt"], "staged parsed")
        check("GitStatus unstaged", status.unstaged.map(\.path) == ["unstaged.txt"], "unstaged parsed")
        check("GitStatus untracked", status.untracked.map(\.path) == ["new file.txt"], "untracked parsed")

        let edgeSample = [
            "2 R. N... 100644 100644 100644 abcdef1 abcdef2 R100 renamed.txt",
            "old.txt",
            "u UU N... 100644 100644 100644 100644 abcdef1 abcdef2 abcdef3 conflict.txt",
            ""
        ].joined(separator: "\0")
        let edgeStatus = GitStatus.parse(Data(edgeSample.utf8))
        check(
            "GitStatus rename",
            edgeStatus.changes.contains {
                $0.path == "renamed.txt" && $0.originalPath == "old.txt" && $0.kind == .renamed
            },
            "rename source parsed"
        )
        check(
            "GitStatus conflict",
            edgeStatus.changes.contains { $0.path == "conflict.txt" && $0.kind == .conflicted },
            "conflict parsed"
        )
    }

    @MainActor
    private static func verifyGitOperations(
        root: URL,
        check: (_ name: String, _ condition: Bool, _ detail: String) -> Void
    ) async {
        let command = GitCommand()
        func git(_ arguments: [String], in repository: URL) throws -> Data {
            try command.run(arguments: arguments, workspacePath: repository.path)
        }

        let repository = root.appendingPathComponent("git", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
            _ = try git(["init", "-q"], in: repository)
            let oldName = "old name.txt"
            let newName = "new name.txt"
            try Data("rename content\n".utf8).write(
                to: repository.appendingPathComponent(oldName)
            )
            _ = try git(["add", "--", oldName], in: repository)
            _ = try git([
                "-c", "user.name=Atelier Selftest",
                "-c", "user.email=atelier-selftest@example.invalid",
                "commit", "-qm", "initial"
            ], in: repository)
            _ = try git(["mv", "--", oldName, newName], in: repository)

            try await GitService().unstage(
                path: newName,
                originalPath: oldName,
                workspacePath: repository.path
            )
            let cached = try git(["diff", "--cached", "--name-only"], in: repository)
            let renamedFileExists = FileManager.default.fileExists(
                atPath: repository.appendingPathComponent(newName).path
            )
            check(
                "Git unstage rename",
                cached.isEmpty && renamedFileExists,
                "index cleared and worktree preserved"
            )
        } catch {
            check("Git unstage rename", false, error.localizedDescription)
        }
    }
}
