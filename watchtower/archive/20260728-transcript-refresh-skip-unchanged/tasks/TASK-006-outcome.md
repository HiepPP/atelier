# TASK-006 Outcome

## Outcome

Status: DONE

Changed:
- Added `GitRefreshThrottlePolicy` in [app/Atelier/Sources/Atelier/Git/ChangesView.swift](../../app/Atelier/Sources/Atelier/Git/ChangesView.swift):
  pure delay function of the time since the last filesystem-driven spawn. Debounce stays
  300 milliseconds; spawns are now spaced at least 2 seconds apart.
- `GitWorkspaceModel.invalidate` records `lastFilesystemRefreshSpawn` and uses the policy
  delay instead of a fixed 300 millisecond sleep. Trailing behavior kept: the newest event
  always ends with one refresh. Manual `refresh()` from user and git actions is unchanged.
- Added [app/Atelier/Tests/AtelierTests/GitRefreshThrottlePolicyTests.swift](../../app/Atelier/Tests/AtelierTests/GitRefreshThrottlePolicyTests.swift)
  with six cases: first spawn, right-after spawn, inside window, window edge, quiet period,
  negative elapsed.

Contract:
- Filesystem events spaced past the debounce no longer spawn one `git status` each; a burst
  collapses to at most one spawn per 2 second window, always ending with a trailing refresh.
- `GIT_OPTIONAL_LOCKS=0` was already set, so there was no index feedback loop; the fix is
  spawn spacing only.
- GitNexus impact on `invalidate` and `refreshStatus` reported HIGH (callers: workspace
  watcher, rename, trash, gitignore). Signatures and caller behavior unchanged; only internal
  timing moved.

Verified:
- `swift build --package-path app/Atelier` -> passes.
- `swift test --package-path app/Atelier` -> 332 tests, only the three known flaky timing
  failures (PrecommitWhisper, WorkspaceToolExecutor cancel, WorkspaceSearch cancel). The six
  new policy tests pass.
- `--selftest` -> `SELFTEST: ALL PASS`.
- Launched via `build_and_run.sh run`, wrote to a workspace file every 0.5 seconds for 30
  seconds, ran `sample <PID> 25` during the loop. Top-of-stack list contains no
  `GitOutputBox.capture` or `GitCommand.run`; those symbols appear only on reader threads
  parked in the `read` syscall waiting for pipe EOF, which is blocked time, not CPU.
  Sample saved during the session; compute frames were AttributeGraph and SwiftUI layout
  from the file-tree refresh path, outside this TASK.
- Idle CPU after the burst: median 1.0 percent, max 3.7 percent over 60 seconds -> inside
  the 0.2 to 2 percent idle rule.
- During-burst CPU median was 11.3 percent, owned by per-event file-tree and SwiftUI refresh,
  not git subprocess work. Recorded as a candidate follow-up, not a regression of this TASK.
