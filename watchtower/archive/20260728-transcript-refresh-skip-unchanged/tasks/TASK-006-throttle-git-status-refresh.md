# TASK-006 Throttle Git status refresh to one spawn per burst

Group: standalone

## Brief

Goal: a burst of filesystem events during agent activity spawns at most one `git status`
subprocess per throttle window, so a sample taken during transcript writes no longer ranks
`GitOutputBox.capture` and `GitCommand.run` at the top.

Change: pure 300 millisecond trailing debounce -> trailing debounce plus a minimum spacing
throttle between git subprocess spawns, with no cancel-and-respawn of an in-flight status run
from the filesystem path.

Why the current code still bursts:

- `GitModel.invalidate` at [app/Atelier/Sources/Atelier/Git/ChangesView.swift](../../app/Atelier/Sources/Atelier/Git/ChangesView.swift)
  line 389 collapses only events closer than 300 milliseconds. Agent activity emits events
  spaced 0.3 to 1 second apart, so each delivery spawns its own `git status` with
  `--ignored=matching --untracked-files=all`, which walks the whole tree.
- `refreshStatus` at line 358 cancels the in-flight status task before starting a new one,
  so overlapping invalidations waste a partly finished subprocess and spawn another.
- `GIT_OPTIONAL_LOCKS=0` is already set in
  [app/Atelier/Sources/Atelier/Git/GitService.swift](../../app/Atelier/Sources/Atelier/Git/GitService.swift)
  line 292, so there is no index-write feedback loop. The cost is spawn frequency, not a loop.

How:

- In `GitModel`, record when the last filesystem-driven refresh started.
- In `invalidate`, compute the delay as the larger of 300 milliseconds and the time remaining
  until 2 seconds have passed since the last spawn. Keep trailing behavior: the newest event
  always ends with one refresh.
- While a filesystem-driven status refresh is in flight, do not cancel it; let the throttle
  schedule one trailing rerun after it, so a burst ends with exactly one final subprocess.
- Keep manual refresh (`refresh()` from user actions and git actions) immediate and unchanged.
- Extract the delay decision into a small testable policy (pure function of last-spawn time and
  now) so a unit test covers the spacing without spawning processes.

Files:

- [app/Atelier/Sources/Atelier/Git/ChangesView.swift](../../app/Atelier/Sources/Atelier/Git/ChangesView.swift) (throttle in `invalidate` and `refreshStatus`)
- [app/Atelier/Tests/AtelierTests/](../../app/Atelier/Tests/AtelierTests/) (unit test for the spacing policy)

Expected result:

- Ten invalidations spaced 0.5 seconds apart produce at most two `git status` spawns
  (one leading window, one trailing), not ten.
- A 25 second `sample` of Atelier taken while workspace files are written in a loop no longer
  shows `GitOutputBox.capture` or `GitCommand.run` as the top app-owned frames.
- Saving a file still updates the Changes panel within about 2.5 seconds.

Prompt (optional):

```text
Invoke $swiftui-expert-skill first. Run GitNexus impact on GitModel.invalidate and
GitModel.refreshStatus before editing. Keep the change inside GitModel plus one test file.
```

## Verify

- `swift build --package-path app/Atelier` -> passes.
- `swift test --package-path app/Atelier` -> no new failures beyond the three known flaky timing tests.
- `app/Atelier/.build/debug/Atelier --selftest` -> prints `SELFTEST: ALL PASS`.
- Launch via `app/Atelier/scripts/build_and_run.sh run`, drive workspace writes with a loop
  (`for i in $(seq 1 50); do echo x >> <workspace>/tmp-burst.txt; sleep 0.5; done`), run
  `sample <PID> 25` during the loop -> `GitOutputBox.capture` and `GitCommand.run` absent from
  the top app-owned frames; remove the temp file after.
- Idle CPU after the burst ends stays at or below 2 percent median over a 60 second window.
  The during-burst CPU is dominated by file-tree and SwiftUI refresh, which is outside this TASK.
