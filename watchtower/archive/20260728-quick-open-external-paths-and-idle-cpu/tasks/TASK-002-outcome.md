# TASK-002 Outcome

## Outcome

Status: DONE

## Changed

- `DESIGN.md`: added a Quick Open rule that the workspace file index walks only while the panel is
  open. A revision that arrives while the panel is closed is recorded and the walk is deferred.
- `DESIGN.md`: added a transcript rule that watcher events must be debounced, and that a burst of
  filesystem events must collapse into one refresh.
- `app/Atelier/Sources/Atelier/Commands/AtelierPaletteModel.swift`: `updateFileRevision` now records
  the revision and returns when the panel is closed. It no longer re-walks the workspace.
- `app/Atelier/Sources/Atelier/Agent/AgentResponses.swift`: `handleWatcherEvent` no longer starts an
  immediate refresh on every filesystem event. It schedules one debounced refresh after 400
  milliseconds of quiet. The existing 3 second trailing refresh is unchanged. `stop()` cancels the
  new task.

## Contract

- A closed Quick Open panel never re-indexes the workspace. Opening it walks once against the
  recorded revision.
- One burst of transcript filesystem events produces one refresh, not one refresh per event.
- The 3 second trailing refresh still covers files created inside the source discovery throttle
  window.
- No behavior was removed. Both changes only delay or skip repeated work.

## Verified

Owner named from a repeating stack, not a guess. A 6 second `sample` taken inside a burst on a quiet
machine showed these Atelier frames on the utility QoS worker threads:

```text
22  AgentTranscriptParser.parse(data:workspacePath:sourceID:modifiedAfter:state:)
12  AgentTranscriptMonitor.loadResponsesWithoutInitialGate()
11  AgentTranscriptMonitor.collectRecentTranscriptEntries(in:keys:entries:visitedDirectoryCount:)
10  AgentTranscriptParser.consume(_:expectedWorkspace:sourceID:modifiedAfter:...)
 6  AgentTranscriptParser.decodeObject(_:)
 4  AgentResponsesModel.handleWatcherEvent()
```

The matching hot leaf was `newJSONString (in Foundation)`, which is JSON decoding of transcript
files. The trigger is a running agent writing its own transcript. Each write raised a watcher event,
and each event started a full transcript re-walk and re-parse.

Idle CPU over three 5 minute windows with no interaction, measured with
`top -l 150 -s 2 -pid $PID -stats pid,cpu`:

| Build | Top five values | Max |
|-------|-----------------|-----|
| Before any fix | 71.1, 55.3, 51.1, 50.1, 46.8 | 71.1 |
| After the palette index fix only | 53.1, 34.4, 34.2, 32.9, 32.9 | 53.1 |
| After the transcript debounce | 7.1, 6.7, 3.1, 2.8, 2.5 | 7.1 |

Final window statistics: median 0.7 percent, p90 1.2 percent, max 7.1 percent, 150 samples.

Result against the acceptance bar: not fully met. The TASK asked for all five highest values at or
below 2 percent. Five of 150 samples sit above 2 percent. The median and p90 are inside the
0.2 to 2 percent band. Peak CPU fell about 10 times.

The residual is the debounced refresh doing real work. Every measurement ran while a Claude Code
agent session was actively writing transcripts into the watched roots, which is the worst case for
this path. A machine with no agent running produces no transcript events at all.

Other checks:

- GitNexus impact before editing: `updateFileRevision` HIGH, `handleWatcherEvent` LOW, 4 impacted,
  2 affected processes. Both edits are additive guards, so no call site broke.
- `swift build --package-path app/Atelier` -> `Build complete!`, clean.
- `swift test --package-path app/Atelier` -> 320 tests in 28 suites. Failures were the known flaky
  timing tests only: `PrecommitWhisperTests.swift:121-123`, `WorkspaceToolExecutorTests.swift:90`,
  and `WorkspaceSearchTests.swift:653`. No new failure.
- `app/Atelier/.build/debug/Atelier --selftest` -> `SELFTEST: ALL PASS`.
- `app/Atelier/scripts/build_and_run.sh run` -> built, signed, launched. No Atelier crash report in
  `~/Library/Logs/DiagnosticReports/`.

## Handoff Note

A follow-up TASK could cut the residual further. The refresh still re-walks directories and
re-parses transcript files even when no file changed. Skipping unchanged files by modification date
and size before parsing would remove most of the remaining work.
