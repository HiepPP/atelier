# TASK-002 Agent detection service

Group: B (threads panel implementation)

## Brief

Goal: Add a light, testable way to tell if a terminal runs an agent, and to read that agent name. The panel model in TASK-003 uses this. Keep the pure matching logic separate from the syscall bridge so tests can cover it.

Change: No agent signal today -> a terminal can report its foreground agent name, or nil when it sits at the shell.

How:

- Add a pure policy type, for example `AgentDetectionPolicy`, in a new file under [app/Atelier/Sources/Atelier/Terminal/](app/Atelier/Sources/Atelier/Terminal/). It holds the default agent token list `claude`, `codex`, `aider`, `gemini`, `cursor-agent`. It exposes a function that takes argv words and returns the matched agent name or nil. Match a token that equals argv[0] last path component, or any argv word equal to a token. Keep it case sensitive and simple.
- Add a foreground-process reader. Given a pty master fd, call `tcgetpgrp(fd)` for the foreground process group id. Return nil when the fd is -1, the result is <= 0, or it equals the shell pid. Otherwise read the argv of that pid with `sysctl` `KERN_PROCARGS2`, then pass the argv words to `AgentDetectionPolicy`.
- Expose the reader through [app/Atelier/Sources/Atelier/Terminal/TerminalController.swift](app/Atelier/Sources/Atelier/Terminal/TerminalController.swift). Add a method that returns the current foreground agent name or nil. It reads `terminal.process.childfd` and `terminal.process.shellPid`, and guards the closed state. Run impact analysis on `TerminalController` before editing it.
- Keep the syscall code off the hot path. The reader runs only when the panel asks. Do not add any timer here.
- Do not log argv, process names, or command text.

Files:

- [app/Atelier/Sources/Atelier/Terminal/AgentDetection.swift](app/Atelier/Sources/Atelier/Terminal/AgentDetection.swift) (new: `AgentDetectionPolicy` plus the argv reader helper)
- [app/Atelier/Sources/Atelier/Terminal/TerminalController.swift](app/Atelier/Sources/Atelier/Terminal/TerminalController.swift) (add a foreground agent-name accessor that reads `process.childfd` and `process.shellPid`)

Expected result:

- `AgentDetectionPolicy` returns the agent name for argv like `["claude"]` or `["node", "/path/claude", "run"]`, and nil for `["zsh"]` or `["ls", "-la"]`.
- `TerminalController` returns an agent name while an agent runs in the foreground, and nil when the terminal sits at the shell.
- No timer and no background work is added.

Prompt (optional):

```text
Run gitnexus_impact on TerminalController before editing it. Report the blast radius. Keep the pure agent-matching logic in AgentDetection.swift so unit tests do not need a live pty.
```

## Verify

- `swift build --package-path app/Atelier` -> builds with no error.
- Add unit tests under [app/Atelier/Tests/AtelierTests/](app/Atelier/Tests/AtelierTests/) for `AgentDetectionPolicy`. `swift test --package-path app/Atelier` -> the new cases pass: `["claude"]` -> claude, `["node","/x/claude","run"]` -> claude, `["zsh"]` -> nil, `["git","status"]` -> nil.
- `rg -n "tcgetpgrp|KERN_PROCARGS2" app/Atelier/Sources/Atelier/Terminal` -> the reader exists and lives in the Terminal module.
