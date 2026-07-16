import Foundation
import SwiftTerm

@MainActor
struct TerminalProcessService {
    func start(in terminal: LocalProcessTerminalView, workspacePath: String) {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let shellName = (shell as NSString).lastPathComponent
        var environment = ProcessInfo.processInfo.environment.map { "\($0.key)=\($0.value)" }
        environment.removeAll { $0.hasPrefix("TERM=") }
        environment.append("TERM=xterm-256color")
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
}
