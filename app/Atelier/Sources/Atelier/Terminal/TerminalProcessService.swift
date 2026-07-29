import Darwin
import Foundation
import SwiftTerm

@MainActor
struct TerminalProcessService {
    func start(in terminal: LocalProcessTerminalView, workspacePath: String) {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let shellName = (shell as NSString).lastPathComponent
        let environment = Self.configuredEnvironment(
            from: ProcessInfo.processInfo.environment
        ).map { "\($0.key)=\($0.value)" }
        terminal.startProcess(
            executable: shell,
            args: [],
            environment: environment,
            execName: "-\(shellName)",
            currentDirectory: workspacePath
        )
    }

    func stop(_ terminal: LocalProcessTerminalView) {
        let shellPid = terminal.process?.shellPid ?? 0
        terminal.terminate()
        // SwiftTerm's terminate() sends SIGTERM and cancels its child monitor,
        // so the shell is never reaped and stays a zombie per closed tab.
        // Zombies accumulate toward the per-user process limit until forkpty
        // and git subprocess spawns start failing. Reap it here.
        Self.reap(shellPid: shellPid)
    }

    nonisolated static func reap(
        shellPid: pid_t,
        killEscalationDelay: Duration = .seconds(3)
    ) {
        guard shellPid > 0 else { return }
        DispatchQueue.global(qos: .utility).async {
            var status: Int32 = 0
            let pollInterval: Duration = .milliseconds(50)
            var waited: Duration = .zero
            while waited < killEscalationDelay {
                let reaped = waitpid(shellPid, &status, WNOHANG)
                if reaped == shellPid { return }
                if reaped == -1 {
                    // ECHILD: already reaped by SwiftTerm's exit monitor or
                    // never our child. Either way there is nothing to reap.
                    return
                }
                usleep(useconds_t(pollInterval.components.attoseconds / 1_000_000_000_000))
                waited += pollInterval
            }
            // The shell ignored SIGTERM; SIGKILL cannot be ignored, so the
            // blocking waitpid below returns promptly.
            kill(shellPid, SIGKILL)
            if waitpid(shellPid, &status, 0) == -1 {
                let reapError = String(cString: strerror(errno))
                AppLogger.terminal.warning(
                    "Could not reap terminated shell \(shellPid): \(reapError, privacy: .public)"
                )
            }
        }
    }

    nonisolated static func configuredEnvironment(
        from environment: [String: String]
    ) -> [String: String] {
        var environment = environment
        // Launching Atelier from an agent shell leaks that agent's session markers into the
        // app process, and a nested CLI would then treat this terminal as its own child.
        for key in environment.keys where key.hasPrefix("CLAUDE_CODE_") {
            environment.removeValue(forKey: key)
        }
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        environment["CLICOLOR"] = "1"
        environment["TERM_PROGRAM"] = "Atelier"
        environment.removeValue(forKey: "NO_COLOR")
        return environment
    }
}
