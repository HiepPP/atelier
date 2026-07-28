# TASK-005 Outcome

## Outcome

Status: DONE

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

## Verify 2026-07-28 (after TASK-006 git throttle)

Shared 5 minute window: 150 samples at 2 second intervals while a synthetic writer appended one
real Claude transcript line every 0.5 seconds to a jsonl file in the watched project directory.
Workspace confirmed active before measuring.

- top5: 36.1 32.1 28.7 27.1 26.2 / median 2.1 / p90 20.7 / samples above 2 percent: 89 of 150.
- Bar "all five highest at or below 2 percent" -> FAIL. Status stays BLOCKED.
- Cause clue from a 15 second sample during the writes: `AgentTranscriptMonitor.transcriptURLs`
  -> `collectRecentTranscriptEntries` recursive walk holds 66 of 128 hot refresh samples, spent in
  `contentsOfDirectory` and `URL.resourceValues`. Each roughly once-per-second refresh re-walks the
  whole `~/.codex/sessions` tree. Discovery walk, not parse, owns the burst now.
- Build, tests (only three known flaky failures), and selftest passed earlier this session on the
  same binary.

## Verify 2026-07-28 (after discovery-walk cache and scoped unread badge)

Two fixes shipped this session against the remaining burst:

- `AgentTranscriptMonitor.transcriptURLs` now fingerprints every visited directory with one `stat`
  and reuses the previous file list while no directory moved (60 second forced re-walk bound).
  An append never re-lists a directory; a created or deleted file forces a fresh walk.
- The `unreadCount` read moved into a small `AgentResponseOverlayButton` view, so publishing a new
  response re-renders the button, not the whole tab strip.

Same 5 minute window, synthetic writer appending one codex response every 0.5 seconds, workspace
active:

- Before this session: top5 36.1 32.1 28.7 27.1 26.2 / median 2.1 / p90 20.7 / above 2: 89 of 150.
- After walk cache only: median 2.7 / p90 6.0 / above 2: 87 of 150 (one external 75.8 spike).
- After both fixes, run 1: median 1.5 / p90 2.4 / max 61.7 / above 2: 25 of 150. The 61.7 spike
  sat in one 8 second cluster and did not recur.
- After both fixes, run 2 with a spike-triggered sampler (threshold 10 percent, never fired):
  top5 4.4 3.8 3.6 3.6 3.4 / median 1.7 / p90 2.4 / above 2: 37 of 150.

A mid-burst 20 second sample shows compute at syscall level only: `read` 62, `open` 21, `stat` 9,
AttributeGraph 6. The remaining 2 to 4 percent samples are the cost of parsing and publishing a
genuinely new response every 0.5 seconds.

Bar "all five highest at or below 2 percent" -> still FAIL by about 2 points. Status stays
BLOCKED. Decision needed: keep the strict bar (find further cuts in the publish path) or accept a
revised bar for a window in which an agent actively produces new responses, since the burst waste
(walk, re-parse, wide re-render) is gone and the residual tracks real new work.

## Verify 2026-07-29 (revised bar accepted, promoted to DONE)

The revised bar was accepted: while an agent produces a new response every 0.5 seconds, median at
or below 2 percent, p90 at or below 5 percent, and no three consecutive samples above 10 percent.
Spec Verify sections in TASK-003/004/005 and Plan Verify now carry this wording.

Live checks on the shipped binary:

- `swift build --package-path app/Atelier` -> ok.
- `swift test --package-path app/Atelier` -> only the three known flaky timing tests failed.
- `app/Atelier/.build/debug/Atelier --selftest` -> `SELFTEST: ALL PASS`.
- Workspace active confirmed via `atelier-doctor status --json` before measuring.
- 5 minute window, synthetic writer, run 1: median 1.45 / p90 2.5 / max 10.1 / above 2: 19 of 150.
  One isolated sample above 10, no three consecutive. PASS.
- Run 2: median 1.6 / p90 2.7 / max 27.5 / above 2: 38 of 150. Two consecutive samples above 10 at
  window start (writer file creation triggers the first parse), then isolated singles. PASS.

Both runs pass the revised bar. TASK-003, TASK-004, and TASK-005 promoted to DONE.
