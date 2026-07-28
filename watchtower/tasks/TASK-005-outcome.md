# TASK-005 Outcome

## Outcome

Status: BLOCKED

## Changed

- `DESIGN.md`: the overlay restores at most 100 final responses from the last three days. Older
  transcripts are never opened, and older responses never reach the panel.
- `app/Atelier/Sources/Atelier/Agent/AgentResponses.swift`: added
  `AgentTranscriptMonitor.defaultHistoryWindow`, three days as a `TimeInterval`.
- `app/Atelier/Sources/Atelier/Workspace/State/WorkspaceSession.swift`: the production monitor now
  receives `modifiedAfter` as now minus that window. The `init` default stays `.distantPast`, so
  tests with dated fixtures keep working.
- `app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift`: added
  `historyWindowSkipsOldTranscripts`.

## Contract

- A transcript file older than three days is never opened.
- A response older than three days is dropped even when its file is recent.
- Everything else in the refresh path is unchanged.

## Verified

- `swift build --package-path app/Atelier` -> `Build complete!`.
- `swift test --package-path app/Atelier` -> 326 tests in 28 suites. Only the known flaky timing
  tests failed: `PrecommitWhisperTests`, `WorkspaceToolExecutorTests.swift:90`, and
  `WorkspaceSearchTests.swift:653`.
- `app/Atelier/.build/debug/Atelier --selftest` -> `SELFTEST: ALL PASS`.
- New test `Monitor reads only transcripts inside the history window` -> passes. The old file is never
  opened, the stale response inside the recent file is dropped, and `parsedByteCount` counts the
  recent file only.
- A temporary probe ran repeated restores against the real transcript roots with the three day
  cutoff, then was removed:

```text
PROBE round=1 responses=25 deltaBytes=16520366 totalBytes=16520366
PROBE round=2 responses=25 deltaBytes=0 totalBytes=16520366
PROBE totalElapsedSeconds=1.55
```

The restore now finishes in one pass of about 1.55 seconds, and the next refresh parses nothing.
Before this plan, the same work was spread across many refreshes and repeated for minutes.

File counts inside the window on this machine: 10 of 83 Claude files, 9.3 MB. Codex still has 62
recent files, 141 MB, and about half are foreign, so the head check skips them.

- `app/Atelier/scripts/build_and_run.sh run` -> built, signed, launched. `atelier-doctor status`
  reported `workspace.active` true before measuring.

Idle CPU with `top -l 150 -s 2`, workspace freshly opened:

| Window | Five highest | Median | p90 | Above 2 percent |
|--------|--------------|--------|-----|-----------------|
| After TASK-004 | 83.4, 62.9, 58.3, 37.4, 30.9 | 0.8 | 23.1 | 49 of 150 |
| After TASK-005 | 48.0, 45.6, 40.5, 39.3, 35.7 | 1.3 | 24.4 | 50 of 150 |

## Blocked

The CPU bar still fails, but the owner has changed. A 25 second `sample` taken while transcript
writes arrived every few seconds ranked these Atelier frames:

```text
112  GitOutputBox.capture(_:limit:)
112  GitOutputBox.capture(_:limit:)
101  GitCommand.run(arguments:workspacePath:maxOutputBytes:allowedExitCodes:)
 90  GitOutputBox.capture(_:limit:)
 89  GitCommand.run(arguments:workspacePath:maxOutputBytes:allowedExitCodes:)
 67  RuntimeDiagnosticsService.tick()
```

`AgentTranscriptMonitor` does not appear in the top fourteen frames. The transcript path now behaves
as intended: one restore pass, then no parsing while nothing changes.

Next decision needed: open a new TASK against Git status refresh. `GitService` spawns `git`
subprocesses and captures their output through `GitOutputBox.capture`, and that path now dominates
the bursts. The repository rule about debouncing filesystem-driven refreshes and collapsing bursts
into one subprocess spawn applies there.

## Note

Concurrent writers were ruled out for the earlier cache-thrash theory: zero codex files changed in a
30 minute check, so discovery churn was not evicting cache entries.
