# TASK-003 Threads panel model

Group: B (threads panel implementation)

## Brief

Goal: Add the data model that turns live sessions and their terminals into workspace thread groups. It keeps a small run-state map so a done thread survives a panel close and reopen while the terminal lives.

Change: No thread data exists -> a `ThreadsPanelModel` produces grouped thread rows on demand, and diffs before it mutates.

How:

- Add value types in a new file under [app/Atelier/Sources/Atelier/Workspace/Models/](app/Atelier/Sources/Atelier/Workspace/Models/):
  - `ThreadStatus` enum with `running` and `done`.
  - `ThreadEntry` with `terminalID: UUID`, `title: String`, `agentName: String`, `status: ThreadStatus`, `startedAt: Date`, and `finishedAt: Date?`. Make it `Equatable` and `Identifiable` by `terminalID`. The view shows a relative time only for done rows, computed from `finishedAt`. Running rows show a running indicator, not a time.
  - `WorkspaceThreadGroup` with `workspaceID: String`, `name: String`, and `threads: [ThreadEntry]`. Make it `Equatable` and `Identifiable`.
- Add a plain input struct `TerminalSnapshot` with `terminalID: UUID`, `title: String`, `workspaceID: String`, `workspaceName: String`, and `agentName: String?`. This keeps the syscall read out of the pure grouping logic, so tests need no live pty.
- Add `ThreadsPanelModel` as an `@Observable` `@MainActor` type. It holds `groups: [WorkspaceThreadGroup]` and a private run-state map keyed by `terminalID`.
- Add `makeSnapshots(sessions:)` that reads each live session, iterates its `terminalTabs` terminal tabs, asks each controller for the foreground agent name (TASK-002), and returns `[TerminalSnapshot]` in rail order. Include every terminal, with `agentName` nil for plain shells, so each workspace shows up as a group. This is the only part that touches the terminal controller.
- Add `refresh(snapshots:now:)` as the pure grouping step. It takes `[TerminalSnapshot]` and the current `Date` (inject `now` so tests stay deterministic). It updates the run-state map and `groups`. Keep every transition idempotent, so a refresh with no real change does not alter timestamps. For each snapshot:
  - If `agentName` is set and the terminal is new or was done: mark running, store the agent name, set `startedAt` to `now`, and clear `finishedAt`.
  - If `agentName` is set and the terminal is already running with the same name: change nothing. Do not bump `startedAt`. This keeps a long-running agent from churning the value each refresh.
  - If `agentName` is nil and the terminal was running: mark done and set `finishedAt` to `now`.
  - If `agentName` is nil and the terminal was already done: change nothing. Keep `finishedAt`.
  - If `agentName` is nil and the terminal never saw an agent: skip it. It is not a thread.
- Drop run-state entries for terminal ids not present in the current snapshots, so closing a terminal removes its thread.
- Build one `WorkspaceThreadGroup` per workspace present in the snapshots, in rail order, each with its agent threads. Include a group even when it has no threads, so the view can show "No threads yet".
- Assign `groups` only when the new value differs from the old value. Use `Equatable` to avoid redundant `@Observable` mutation, per the repo performance rules.
- Own one `ThreadsPanelModel` instance on [app/Atelier/Sources/Atelier/App/AppModel.swift](app/Atelier/Sources/Atelier/App/AppModel.swift). Run impact analysis on `AppModel` before editing it. Pass sessions into `refresh(sessions:)`; do not retain `AppModel` inside the model.

Files:

- [app/Atelier/Sources/Atelier/Workspace/Models/ThreadsPanelModel.swift](app/Atelier/Sources/Atelier/Workspace/Models/ThreadsPanelModel.swift) (new: value types plus the observable model)
- [app/Atelier/Sources/Atelier/App/AppModel.swift](app/Atelier/Sources/Atelier/App/AppModel.swift) (own one `ThreadsPanelModel` instance)

Expected result:

- `refresh(sessions:)` builds one group per live session in rail order.
- A terminal with a running agent produces a running thread. When the agent exits, the next refresh marks it done, and the row stays while the terminal is open.
- Removing a terminal drops its thread on the next refresh.
- `groups` does not change when the derived value is equal, so no redundant invalidation happens.

Prompt (optional):

```text
Run gitnexus_impact on AppModel before editing it. Keep the model MainActor and Observable. Diff with Equatable before assigning groups so a refresh with no change does not trigger a view update.
```

## Verify

- `swift build --package-path app/Atelier` -> builds with no error.
- Add unit tests under [app/Atelier/Tests/AtelierTests/](app/Atelier/Tests/AtelierTests/) that call `refresh(snapshots:now:)` with hand-made `TerminalSnapshot` values. `swift test --package-path app/Atelier` -> cases pass: a running agent yields a running thread; a later nil yields a done thread with `finishedAt` set; a running refresh repeated with the same name does not change `startedAt` or `groups`; a removed terminal drops the thread; a workspace with only shell terminals yields a group with no threads.
- `rg -n "Equatable" app/Atelier/Sources/Atelier/Workspace/Models/ThreadsPanelModel.swift` -> the diff types are Equatable.
