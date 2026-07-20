# TASK-003 read_terminal_output tool

Group: B (terminal intelligence ships as one slice)

## Brief

Goal: give Gemma a read-only tool that returns bounded scrollback from the selected terminal.

Change: Gemma cannot see terminal output -> Gemma can read the last N lines of the selected terminal.

How:

- Add `readTerminalOutput = "read_terminal_output"` to `WorkspaceToolName` in [app/Atelier/Sources/Atelier/Agent/Tools/WorkspaceToolModels.swift](app/Atelier/Sources/Atelier/Agent/Tools/WorkspaceToolModels.swift) with a `lines` integer argument.
- Expose a scrollback snapshot method on [app/Atelier/Sources/Atelier/Terminal/TerminalController.swift](app/Atelier/Sources/Atelier/Terminal/TerminalController.swift) that copies the last N lines from the SwiftTerm buffer on `MainActor` and returns plain text.
- Route execution in [app/Atelier/Sources/Atelier/Agent/Tools/WorkspaceToolExecutor.swift](app/Atelier/Sources/Atelier/Agent/Tools/WorkspaceToolExecutor.swift). Cap lines (default 200, max 400) and characters using the existing bounded-result pattern.
- Return a clear tool error when no terminal tab is selected.
- Do not log terminal content.

Files:

- [app/Atelier/Sources/Atelier/Agent/Tools/WorkspaceToolModels.swift](app/Atelier/Sources/Atelier/Agent/Tools/WorkspaceToolModels.swift) (new tool name and definition)
- [app/Atelier/Sources/Atelier/Agent/Tools/WorkspaceToolExecutor.swift](app/Atelier/Sources/Atelier/Agent/Tools/WorkspaceToolExecutor.swift) (execution and bounds)
- [app/Atelier/Sources/Atelier/Terminal/TerminalController.swift](app/Atelier/Sources/Atelier/Terminal/TerminalController.swift) (scrollback snapshot method)

Expected result:

- Gemma can call `read_terminal_output` and receives the last lines of the selected terminal.
- Output is capped by lines and characters; oversized output is marked truncated.
- Tool fails with a clear message when no terminal is selected.

## Verify

- `swift build --package-path app/Atelier` -> builds clean.
- `swift test --package-path app/Atelier` -> new tests cover line cap, character cap, and no-terminal error.
- Manual: run `ls` in the terminal, ask sidecar what the last command printed -> answer reflects real output.
