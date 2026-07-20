# TASK-007 Session Journal

Group: D (standalone feature on top of the sidecar)

## Brief

Goal: a journal section in the sidecar where Gemma writes short timestamped summaries of the work session.

Change: no session history -> a running list like "17:05 - fixed terminal spacing, tests pass".

How:

- Every 15 minutes of activity, run one bounded Gemma call with: commands from recent terminal lines, changed file list from `git status`, and the current diff stat.
- Ask for one 1-2 line entry describing what happened since the last entry. Append it to an in-memory journal shown in a collapsible sidecar section.
- Skip a cycle when nothing changed since the last entry, when a sidecar request is already running, or when Ollama is unreachable.
- Add copy-all so the journal can become a standup note. Journal is per-session; it clears when the workspace closes.
- Add a toggle to disable the journal, persisted with existing settings storage.

Files:

- [app/Atelier/Sources/Atelier/Agent/](app/Atelier/Sources/Atelier/Agent/) (journal scheduler and entries in sidecar model)
- [app/Atelier/Sources/Atelier/Workspace/Views/ContentView.swift](app/Atelier/Sources/Atelier/Workspace/Views/ContentView.swift) (journal section view)

Expected result:

- After working with terminal and edits, the journal shows timestamped entries matching real activity.
- Idle time produces no entries.

## Verify

- `swift build --package-path app/Atelier` -> builds clean.
- `swift test --package-path app/Atelier` -> tests cover skip-when-idle and scheduler cancellation.
- Manual: run commands and edit a file, wait one cycle (use a short debug interval) -> entry appears and matches the activity.
- Manual: close workspace -> scheduler stops, no further calls.
