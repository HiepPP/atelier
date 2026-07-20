# TASK-005 Terminal Guardian

Group: B (terminal intelligence ships as one slice)

## Brief

Goal: when a foreground command exits non-zero, the sidecar shows an automatic diagnosis card without a user prompt.

Change: user must notice the failure and ask -> sidecar diagnoses the failure on its own.

How:

- Detect foreground command completion and exit code in the terminal layer. Prefer shell integration marks (OSC 133) when available; fall back to a prompt-return heuristic if not.
- On non-zero exit, run one bounded Gemma call: last 200 scrollback lines plus exit code, asking for a short diagnosis and a suggested fix command.
- Render the result as a dismissible card at the top of the sidecar. Never steal focus, never show a modal.
- Debounce: at most one Guardian run at a time; drop new triggers while one runs. Skip entirely when Ollama is unreachable.
- Add a toggle to disable Guardian, persisted with existing settings storage.
- Do not log scrollback content.

Files:

- [app/Atelier/Sources/Atelier/Terminal/TerminalController.swift](app/Atelier/Sources/Atelier/Terminal/TerminalController.swift) (exit detection hook)
- [app/Atelier/Sources/Atelier/Agent/](app/Atelier/Sources/Atelier/Agent/) (Guardian trigger logic in sidecar model)
- [app/Atelier/Sources/Atelier/Workspace/Views/ContentView.swift](app/Atelier/Sources/Atelier/Workspace/Views/ContentView.swift) (diagnosis card view)

Expected result:

- A failing command produces a diagnosis card in the sidecar within a few seconds.
- A succeeding command produces no card.
- Toggling Guardian off stops all automatic calls.

## Verify

- `swift build --package-path app/Atelier` -> builds clean.
- `swift test --package-path app/Atelier` -> tests cover exit-code detection and debounce.
- Manual: run `cat /missing-file` -> card appears with a relevant diagnosis; run `echo ok` -> no card.
- Manual: turn Guardian off, run a failing command -> no card, no network call.
