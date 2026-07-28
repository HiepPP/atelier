# TASK-005 Restore only the last three days of transcript history

Group: standalone

## Brief

Goal: read only recent history. Give the transcript monitor a three day cutoff, so old transcript
files are never opened and old responses never reach the panel.

Change: the monitor restores all history it can find -> it restores the last three days.

Why this is the right lever, from TASK-004:

- The backlog is wide, not deep. About 97 own transcript files hold 23 responses for this workspace.
- A cold restore parses 16.5 MB in 1.6 seconds, and the warmup keeps CPU high for about 95 seconds
  after a workspace opens.
- The monitor already has the needed parameter. `AgentTranscriptMonitor.init` takes `modifiedAfter`,
  which filters files during the walk and responses during the parse.
  [app/Atelier/Sources/Atelier/Workspace/State/WorkspaceSession.swift](../../app/Atelier/Sources/Atelier/Workspace/State/WorkspaceSession.swift)
  line 95 passes nothing, so the default `.distantPast` reads everything.

How:

- Add one constant on `AgentTranscriptMonitor`, for example
  `static let defaultHistoryWindow: TimeInterval = 3 * 24 * 60 * 60`.
- Pass `Date().addingTimeInterval(-AgentTranscriptMonitor.defaultHistoryWindow)` as `modifiedAfter`
  at the production call site in `WorkspaceSession`.
- Keep the `init` default at `.distantPast`, so existing tests with dated fixtures keep working.
- Change nothing else in the refresh path. The fingerprint skip, the newest-first stop, the foreign
  workspace skip, and the first parse cap all stay.
- Update [DESIGN.md](../../DESIGN.md) first. State that the overlay restores at most 100 final
  responses from the last three days, and that older transcripts are never opened.

Files:

- [DESIGN.md](../../DESIGN.md) (state the three day restore window)
- [app/Atelier/Sources/Atelier/Agent/AgentResponses.swift](../../app/Atelier/Sources/Atelier/Agent/AgentResponses.swift)
  (add the window constant)
- [app/Atelier/Sources/Atelier/Workspace/State/WorkspaceSession.swift](../../app/Atelier/Sources/Atelier/Workspace/State/WorkspaceSession.swift)
  (pass the cutoff at line 95)
- [app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift](../../app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift)
  (add a cutoff test)

Expected result:

- A transcript file older than the cutoff is never opened.
- A recent file still loads, and a response older than the cutoff inside it is dropped.
- The response overlay shows recent sessions only.
- Idle CPU stays at or below 2 percent across a 5 minute window that starts right after the workspace
  opens, while an agent writes transcripts.

## Verify

- `swift build --package-path app/Atelier` -> `Build complete!`.
- `swift test --package-path app/Atelier` -> no new failure beyond the known flaky timing tests.
- `app/Atelier/.build/debug/Atelier --selftest` -> `SELFTEST: ALL PASS`.
- New test: one file older than the cutoff and one recent file -> only the recent responses load, and
  `parsedByteCount` counts the recent file only.
- Existing tests that use dated fixtures with the default cutoff still pass.
- Relaunch with `app/Atelier/scripts/build_and_run.sh run`. Confirm
  `app/Atelier/scripts/atelier-doctor status --json` reports `workspace.active` as true before
  measuring, because an app with no workspace reads a false idle.
- Measure while an agent writes transcripts. Revised bar (accepted 2026-07-29): while an agent
  produces a new response every 0.5 seconds, median at or below 2 percent, p90 at or below
  5 percent, and no three consecutive samples above 10 percent. The strict idle rule (0.2 to 2 percent)
  applies only to windows with no new responses:

```bash
PID=$(pgrep -x Atelier | head -1)
top -l 150 -s 2 -pid $PID -stats pid,cpu | rg "^ *$PID" | awk '{print $2}' | sort -rn | head -5
```

- Open the response overlay and confirm recent sessions still appear.
- Record median, p90, max, and the count of samples above 2 percent in the outcome sidecar.
