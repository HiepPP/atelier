# TASK-006 Claude Code briefing action

Group: C (standalone feature on top of the sidecar)

## Brief

Goal: a Brief action where Gemma gathers workspace context and writes a ready prompt, then pastes it into the selected terminal for Claude Code.

Change: user hand-writes context into agent prompts -> Gemma composes a self-contained briefing prompt in one click.

How:

- Add a Brief quick action, visible when a terminal tab exists.
- Gemma call: gather open file paths, current git diff summary (via `read_git_diff`), and recent terminal lines (via `read_terminal_output`), then write one concise, self-contained prompt describing the current work state.
- Show the generated prompt in the sidecar with two buttons: copy, and paste into terminal via the existing `pasteIntoSelectedTerminal` in [app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift](app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift).
- Paste only on explicit button press. Never send Enter; the user reviews and submits.

Files:

- [app/Atelier/Sources/Atelier/Agent/](app/Atelier/Sources/Atelier/Agent/) (briefing prompt logic in sidecar model)
- [app/Atelier/Sources/Atelier/Workspace/Views/ContentView.swift](app/Atelier/Sources/Atelier/Workspace/Views/ContentView.swift) (Brief action and result view)

Expected result:

- Brief produces a prompt that names real open files and the real diff state.
- Paste puts the text into the terminal input without executing it.

## Verify

- `swift build --package-path app/Atelier` -> builds clean.
- Manual: open two files, edit one, run Brief -> generated prompt names those files and the change.
- Manual: press paste -> text appears in the terminal, no command runs until Enter.
