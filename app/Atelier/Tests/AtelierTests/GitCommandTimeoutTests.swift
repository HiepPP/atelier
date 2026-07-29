import Foundation
import Testing
@testable import Atelier

@Suite("Git command timeout policy")
struct GitCommandTimeoutTests {
    @Test("Network transfer subcommands get the long deadline")
    func longRunningSubcommands() {
        for subcommand in ["push", "fetch", "pull", "clone"] {
            #expect(
                GitCommandTimeoutPolicy.deadline(for: [subcommand])
                    == GitCommandTimeoutPolicy.longRunningDeadline
            )
        }
        #expect(
            GitCommandTimeoutPolicy.deadline(for: ["push", "-u", "origin", "main"])
                == GitCommandTimeoutPolicy.longRunningDeadline
        )
    }

    @Test("Local subcommands get the standard deadline")
    func localSubcommands() {
        for subcommand in ["status", "diff", "log", "add", "commit", "restore", "branch"] {
            #expect(
                GitCommandTimeoutPolicy.deadline(for: [subcommand])
                    == GitCommandTimeoutPolicy.standardDeadline
            )
        }
    }

    @Test("Global options before the subcommand are skipped")
    func globalOptions() {
        #expect(
            GitCommandTimeoutPolicy.subcommand(
                in: ["-c", "user.name=Tester", "commit", "-qm", "initial"]
            ) == "commit"
        )
        #expect(
            GitCommandTimeoutPolicy.subcommand(
                in: ["--git-dir", "/tmp/remote.git", "rev-parse", "refs/heads/main"]
            ) == "rev-parse"
        )
        #expect(
            GitCommandTimeoutPolicy.deadline(
                for: ["-c", "http.lowSpeedLimit=1", "-C", "/tmp/repo", "fetch", "origin"]
            ) == GitCommandTimeoutPolicy.longRunningDeadline
        )
    }

    @Test("Missing subcommand falls back to the standard deadline")
    func missingSubcommand() {
        #expect(GitCommandTimeoutPolicy.subcommand(in: []) == nil)
        #expect(GitCommandTimeoutPolicy.subcommand(in: ["-c", "user.name=Tester"]) == nil)
        #expect(
            GitCommandTimeoutPolicy.deadline(for: [])
                == GitCommandTimeoutPolicy.standardDeadline
        )
    }

    @Test("Duration converts to fractional seconds")
    func durationSeconds() {
        #expect(GitCommandTimeoutPolicy.seconds(.seconds(120)) == 120)
        #expect(GitCommandTimeoutPolicy.seconds(.milliseconds(250)) == 0.25)
    }

    @Test("A git command past its deadline is terminated and reports a timeout")
    nonisolated func commandTimesOut() async throws {
        let repository = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "atelier-tests-git-command-timeout-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: repository,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: repository) }
        let command = GitCommand()
        // Detached: GitCommand.run blocks on waitUntilExit. Run on the main
        // actor it starves every concurrently scheduled main-actor test.
        func git(
            _ arguments: [String],
            deadline: Duration? = nil
        ) async throws -> Data {
            try await Task.detached {
                try command.run(
                    arguments: arguments,
                    workspacePath: repository.path,
                    deadline: deadline
                )
            }.value
        }

        _ = try await git(["init", "-q"])
        try Data("change\n".utf8).write(to: repository.appendingPathComponent("file.txt"))
        _ = try await git(["add", "--", "file.txt"])
        // A pre-commit hook that sleeps blocks the commit without depending on
        // editor environment variables the test host may override.
        let hooks = repository.appendingPathComponent(".git/hooks", isDirectory: true)
        try FileManager.default.createDirectory(at: hooks, withIntermediateDirectories: true)
        let hook = hooks.appendingPathComponent("pre-commit")
        try Data("#!/bin/sh\nsleep 15\n".utf8).write(to: hook)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: hook.path
        )

        // The commit never exits on its own; the deadline must terminate it.
        // The bounded reader wait caps the extra delay the sleeping hook
        // grandchild can add by holding the stderr pipe open.
        let clock = ContinuousClock()
        let start = clock.now
        do {
            _ = try await git(
                [
                    "-c", "user.name=Atelier Tests",
                    "-c", "user.email=atelier-tests@example.invalid",
                    "commit", "-m", "blocked by hook"
                ],
                deadline: .milliseconds(250)
            )
            Issue.record("Expected the commit to time out")
        } catch GitServiceError.timedOut(let arguments, let seconds) {
            #expect(arguments.contains("commit"))
            #expect(seconds == 0.25)
        }
        #expect(clock.now - start < .seconds(10))
    }
}
