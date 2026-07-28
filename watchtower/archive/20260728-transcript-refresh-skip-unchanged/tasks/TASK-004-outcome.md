# TASK-004 Outcome

## Outcome

Status: DONE

## Changed

- `DESIGN.md`: added the rule that a transcript above 1 MiB restores its session header and its newest
  1 MiB only, that the header must stay in the parsed buffer for codex sessions, and that later
  appends still read from the real file end.
- `app/Atelier/Sources/Atelier/Agent/AgentResponses.swift`: `AgentTranscriptMonitor` caps the first
  read of a file above `maximumFirstParseBytes` (1 MiB). The parse buffer is the file head, cut at
  its last newline, followed by the tail started at its first complete line. The cache stores the
  true end offset, so a later append still reads from the real end.
- `app/Atelier/Sources/Atelier/Agent/AgentResponses.swift`: added `cappedParseBuffer(for:tail:)` and
  `readHead(of:)`. `declaresOtherWorkspace(at:)` now reuses `readHead(of:)`.
- `app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift`: added
  `largeTranscriptFirstParseIsCapped`.

## Contract

- A file at or below 1 MiB keeps its current behavior. Append reads keep their current behavior.
- A first read above the cap parses the header plus the newest 1 MiB. Responses earlier in that file
  are not restored.
- The cache holds the real end offset, so an append after a capped read parses only the new bytes.
- `parsedByteCount` counts parsed bytes, not head or skipped bytes.

## Verified

- `swift build --package-path app/Atelier` -> `Build complete!`.
- `swift test --package-path app/Atelier` -> 325 tests in 28 suites. Only the known flaky timing
  tests failed: `PrecommitWhisperTests.swift:122-123` and `WorkspaceSearchTests.swift:653`.
- `app/Atelier/.build/debug/Atelier --selftest` -> `SELFTEST: ALL PASS`.
- New test `Monitor caps the first parse of a large transcript to its tail` -> passes. A 1.7 MB codex
  transcript keeps its newest response, drops its oldest, parses under 1 MiB plus the head, and a
  later append adds exactly the appended bytes.
- A temporary probe ran one cold restore against the real transcript roots for this workspace:
  `responses=23 parsedBytes=16524359 elapsedSeconds=1.61`. The probe file was removed after the run.
- `app/Atelier/scripts/build_and_run.sh run` -> built, signed, launched. No new Atelier report in
  `~/Library/Logs/DiagnosticReports/`.

Idle CPU with `top -l 150 -s 2`, 150 samples, with the workspace freshly opened and a transcript
write driven every 5 seconds:

| Part of the window | Five highest | Median | Above 2 percent |
|--------------------|--------------|--------|-----------------|
| Whole window | 83.4, 62.9, 58.3, 37.4, 30.9 | 0.8 | 49 of 150 |
| Samples 90 to 150 | 5.9, 4.2, 3.7, 3.1, 2.5 | 0.5 | 5 of 61 |

A 10 second `sample` taken after the window showed an idle process. The largest Atelier frames were
`GitOutputBox.capture` at 37, `RuntimeDiagnosticsService.tick` at 30, and
`AgentTranscriptMonitor.loadResponses` at 30, with the monitor time inside `transcriptURLs` rather
than the parser.

## Blocked

The acceptance bar is still not met, but the shape of the cost changed again.

Samples 2 to 47, about 95 seconds after the workspace opened, hold every high reading. After sample
61 the process settles, and the last 61 samples stay at or below 5.9 percent with a median of 0.5.
The parser no longer dominates once the cache is warm.

Cause of the remaining warmup: the backlog is wide, not deep. This workspace has about 97 own
transcript files, and the restore reads up to 1 MiB from each while the 16 MiB per refresh budget
spreads that work across several refreshes. The probe shows the result: 16.5 MB parsed to surface
23 responses.

Next decision needed: bound discovery instead of bounding bytes per file. Two candidates:

- Skip transcripts whose modification date is older than a chosen window, for example 30 days.
- Stop after a run of consecutive files that add no response, since files are already newest first.

## Note

The app relaunched once with no active workspace. The build script signs ad hoc, which can drop the
security-scoped bookmark, and the restore then needs the folder to be opened again. A CPU window
taken in that state measures an idle app: it read max 0.6 percent with zero samples above 2 percent.
Check `app/Atelier/scripts/atelier-doctor status --json` for `workspace.active` before trusting any
transcript measurement.

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

Shared 5 minute window result recorded in
[TASK-005-outcome.md](TASK-005-outcome.md): top5 4.4 3.8 3.6 3.6 3.4, median 1.7, p90 2.4,
above 2 percent 37 of 150. The strict bar still fails by about 2 points; the residual tracks
publishing genuinely new responses, not burst waste. Status stays BLOCKED pending the bar
decision.

## Verify 2026-07-29 (revised bar accepted, promoted to DONE)

Revised bar accepted and recorded in [TASK-005-outcome.md](TASK-005-outcome.md): both 5 minute
windows pass (run 1 median 1.45 / p90 2.5, run 2 median 1.6 / p90 2.7, no three consecutive
samples above 10 percent). Build, tests (three known flaky only), and selftest passed live.
Status: DONE.
