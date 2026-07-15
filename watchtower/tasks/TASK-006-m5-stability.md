# TASK-006 M5 stability and performance pass

Group: M5 (hardening milestone, depends on M1 to M4)

## Brief

Goal: Make the app stable and fast. Meet the performance targets in [PLAN.md](PLAN.md).

Change: features work -> features stay fast, never block the UI, and handle edge cases.

How:

- Confirm the UI never waits on git. Run all git work off the main thread with cancellation.
- Cap FSEvents load: debounce, coalesce events, and watch only the active workspace.
- Handle large files and binary files in the viewer without high memory or hangs.
- Test a large repo: git refresh stays in the background and does not freeze the UI.
- Handle renamed, deleted, and binary files in the diff view.
- Measure idle CPU and memory. Fix leaks and busy loops.

Files:

- [app/Atelier/Sources/Atelier/GitService.swift](app/Atelier/Sources/Atelier/GitService.swift) (cancellation, background)
- [app/Atelier/Sources/Atelier/FileWatcher.swift](app/Atelier/Sources/Atelier/FileWatcher.swift) (debounce, coalesce)
- [app/Atelier/Sources/Atelier/FileViewer.swift](app/Atelier/Sources/Atelier/FileViewer.swift) (large file handling)
- [app/Atelier/Sources/Atelier/DiffView.swift](app/Atelier/Sources/Atelier/DiffView.swift) (renamed, deleted, binary)

Expected result:

- Opening a file stays under the target time. The UI is never blocked by git.
- Only one FSEvents watcher runs, for the active workspace.
- Idle CPU is near zero and memory stays under the budget.
- Edge case files render without crash or garbage.

## Verify

- cd app/Atelier && swift build -> ok (build complete).
- Open a large repo, edit files fast -> UI stays responsive, no freeze.
- Check idle CPU near zero and memory under 200 MB in Activity Monitor.
- Open a renamed, a deleted, and a binary file in the diff view -> each renders safely.
