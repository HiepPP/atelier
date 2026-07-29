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
        terminal.terminate()
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
