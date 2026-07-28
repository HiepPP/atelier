# TASK-003 Outcome

## Outcome

Status: BLOCKED

## Changed

- `DESIGN.md`: added the rule that only the head of a transcript is read before its first parse, that
  a head naming another workspace is never parsed in full, and that a head naming no workspace is
  parsed as usual.
- `app/Atelier/Sources/Atelier/Agent/AgentResponses.swift`: `AgentTranscriptParser` gained
  `declaresOtherWorkspace(_:workspacePath:)` and a private `declaredWorkspacePath(_:)` helper.
  `belongsToWorkspace` now builds on the same helper, so
  `AgentTranscriptMermaidParser.belongsToWorkspace` keeps working.
- `app/Atelier/Sources/Atelier/Agent/AgentResponses.swift`: `AgentTranscriptMonitor` reads the first
  16 KiB of a file that has no cache entry. When that head names another workspace, the URL joins a
  `foreignURLs` set and later refreshes skip it before any read. The set is trimmed on discovery the
  same way as `cache`.
- `app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift`: added `foreignTranscriptStaysUnparsed`
  and `headlessTranscriptStillParsed`.

## Contract

- A transcript whose head names another workspace is never parsed in full, and stays skipped as it
  grows.
- A transcript whose head names no workspace is still parsed, so an unknown answer drops nothing.
- Head bytes are not counted in `parsedByteCount`.
- The published responses do not change.

## Verified

- `swift build --package-path app/Atelier` -> `Build complete!`.
- `swift test --package-path app/Atelier` -> 324 tests in 28 suites. Only the known flaky timing
  tests failed: `WorkspaceToolExecutorTests.swift:90` and `WorkspaceSearchTests.swift:653`.
- `app/Atelier/.build/debug/Atelier --selftest` -> `SELFTEST: ALL PASS`.
- New test `Monitor never parses a transcript that names another workspace` -> passes. A 200 line
  foreign file stays unparsed across two refreshes, including after its modification date moves.
- New test `Monitor still parses a transcript whose head names no workspace` -> passes.
- `app/Atelier/scripts/build_and_run.sh run` -> built, signed, launched. No new Atelier report in
  `~/Library/Logs/DiagnosticReports/`.

Idle CPU with `top -l 150 -s 2`, measured while this agent session wrote transcripts:

| Window | Five highest | Median | p90 | Above 2 percent |
|--------|--------------|--------|-----|-----------------|
| Cold start, before TASK-003 | 93.0, 92.8, 83.4, 62.7, 51.6 | 0.6 | 2.4 | 18 of 150 |
| Cold start, after TASK-003 | 97.5, 97.2, 82.1, 76.7, 74.3 | 0.6 | 3.3 | 18 of 147 |
| Warm, after TASK-003 | 65.9, 31.3, 20.0, 16.3, 8.6 | 0.6 | 2.0 | 14 of 148 |

The launch burst itself shrank. Before TASK-003 the first samples after launch read 92.8, 83.4, and
93.0 percent across about 10 seconds. After TASK-003 they read 45.2 and 23.8 percent across about
4 seconds.

## Blocked

The acceptance bar is still not met. It asks for all five highest values at or below 2 percent across
a 5 minute window that starts right after launch.

What remains is a burst that arrives once every few minutes and lasts about 10 seconds. Both windows
after TASK-003 caught one: samples 127 to 132 of the cold window, and one sample of 65.9 percent in
the warm window. A watcher polled instantaneous CPU about 400 times across roughly 15 minutes and saw
nothing above 15 percent during stretches with no transcript writes, so the burst follows transcript
activity rather than a timer.

Cause: the first parse of a transcript that does belong to this workspace still reads the whole file.
Own transcripts here reach 8.3 MB, 7.7 MB, and 5.0 MB. When such a file becomes the newest one, it is
read and parsed from byte zero.

Next decision needed: whether to cap the first parse to the tail of a large file. The panel restores
only the newest 100 responses, so reading the last 1 MiB and starting at the first complete line
would give the same list for far less work. That changes the restore contract for very large files,
so it needs a decision before implementation.
