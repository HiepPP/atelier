# TASK-007 Outcome

## Outcome

Status: DONE

## Changed

- `app/Atelier/Sources/Atelier/Workspace/State/WorkspaceSession.swift`: watcher-driven
  `.workspaceContent` deliveries now go through `scheduleFileTreeInvalidation()`, which reuses
  `GitRefreshThrottlePolicy` (300 ms debounce, 2 second minimum spacing, trailing). Direct user
  actions (create, rename, trash, ignore) still call `invalidateFileTree()` immediately. The task
  is cancelled in `stop()`.
- `app/Atelier/Sources/Atelier/Workspace/Views/ContentView.swift`: `ExplorerFileTree` now takes the
  session and reads `session.fileTreeRevision` inside its own body, so a revision bump re-renders
  only the tree view, not the sidebar or the split surface.
- `app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift`: extracted
  `AgentResponseOverlayButton` so the `unreadCount` read leaves the large tab-strip body. A new
  response re-renders only the button. (Shipped for the transcript CPU bar; same churn class.)
- `DESIGN.md`: added the file-tree invalidation throttle rule and the scoped revision read.

## Contract

- A workspace write burst bumps the file-tree revision at most once per 2 seconds, trailing.
- A revision bump re-renders the explorer tree only.
- Create, rename, and delete still reach the tree within about one second from a quiet state.

## Verified

- `swift build --package-path app/Atelier` -> ok.
- `swift test --package-path app/Atelier` -> only the three known flaky timing tests failed.
- `app/Atelier/.build/debug/Atelier --selftest` -> `SELFTEST: ALL PASS`.
- Profile before editing (0.5 second append loop to one workspace file, 30 top samples at
  2 seconds): median 16.9 percent, max 21.7. Sample top of stack: `AG::Graph::propagate_dirty`
  134, `UpdateStack::update` 111, `Subgraph::update` 91, `read` 400. Re-rendering bodies:
  GemmaSidecarView, WorkspaceView.workspaceSurface/workspaceSidebar, TerminalTabs,
  AgentResponseOverlayButton.
- Same loop after the fix: median 1.4 percent, max 2.2 (bar: at or below 5, baseline 11.3).
  Sample shows AttributeGraph at 5 samples; dominant compute path gone.
- Tree freshness via `atelier-doctor` `fileTree.rootEntryCount`: 17 -> 18 within 3 seconds of
  creating a root file, back to 17 after deleting it. Temp files removed.
- GitNexus impact on `invalidateFileTree` returned HIGH (6 direct callers incl. startup and user
  actions); mitigated by leaving `invalidateFileTree` untouched and throttling only the watcher
  call site.
