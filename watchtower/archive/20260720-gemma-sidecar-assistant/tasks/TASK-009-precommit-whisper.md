# TASK-009 Pre-commit Whisper

Group: F (standalone feature on top of the sidecar)

## Brief

Goal: Gemma scans the unstaged diff in the background and flags leftover debug prints, new TODOs, secret-like strings, and commented-out code.

Change: leftovers reach commits unnoticed -> sidecar shows a quiet badge with findings before commit.

How:

- Watch the unstaged diff with the existing Git layer. On change, debounce a few seconds, then run one bounded Gemma call with the diff (capped by the existing character limits).
- Ask for findings only in four categories: debug print, new TODO, secret-like string, commented-out code. Each finding names file and line.
- Show a badge with the finding count on the sidecar; expanding lists findings. No finding, no badge. Advisory only; never blocks commits.
- Only one scan runs at a time; a newer diff cancels the running scan. Skip when the diff is empty or Ollama is unreachable.
- Never log diff content. Redact any secret-like value to its first four characters in the UI.

Files:

- [app/Atelier/Sources/Atelier/Agent/](app/Atelier/Sources/Atelier/Agent/) (whisper scan logic in sidecar model)
- [app/Atelier/Sources/Atelier/Workspace/Views/ContentView.swift](app/Atelier/Sources/Atelier/Workspace/Views/ContentView.swift) (badge and findings list)

Expected result:

- Adding `print("debug")` to a Swift file produces a finding within seconds of the debounce.
- Reverting the change clears the badge on the next scan.

## Verify

- `swift build --package-path app/Atelier` -> builds clean.
- `swift test --package-path app/Atelier` -> tests cover debounce, cancellation, and empty-diff skip.
- Manual: add a debug print -> badge appears with the file and line; revert -> badge clears.
- Manual: add a fake token string -> finding shows the value redacted.
