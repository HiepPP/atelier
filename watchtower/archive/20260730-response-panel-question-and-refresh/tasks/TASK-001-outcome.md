# TASK-001 Outcome

## Status

DONE

## Changed

- `app/Atelier/Sources/Atelier/Agent/AgentResponses.swift`
  - `AgentResponsesModel.refresh(showProgress:markLoadedResponsesRead:)` now coalesces instead of
    dropping. A call that finds a refresh in flight sets `needsAnotherRefresh`; the in-flight call
    runs one more pass after it finishes. The load body moved into a new private
    `load(markLoadedResponsesRead:)`.
  - Added `hasUserSelectedSession`. While it is false, a refresh that adds responses moves
    `selectedSession` to `sessionSummaries.first?.session`. `selectSession(_:)` sets it for a real
    pick and clears it for `nil`. The assignment is guarded on inequality, so an `@Observable`
    mutation only fires on a real change.
  - `loadResponsesWithoutInitialGate` tracks `skippedUncachedFile` and ends with
    `hasMergedResult = !skippedUncachedFile`, so a pass that skipped a discovered file without
    caching it (byte-budget skip, failed attribute read, failed data read) does not arm the
    unchanged-fingerprint shortcut for the next pass.
  - `TranscriptDirectoryWatcher` FSEvents latency lowered from `1.0` to `0.3`.
- `app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift`
  - New tests: `byteBudgetSkipRetriedOnNextRefresh`, `automaticSelectionFollowsNewestSession`,
    `manualSelectionSurvivesNewerSession`, `refreshDuringRefreshRunsOnceMore`.
  - `SuspendingAgentResponseSource` gained `callCount`.
- `DESIGN.md`, `### Agent Responses`: added the newest-session follow rule, the refresh-coalescing
  rule, the 0.3 second watcher latency rule, and the no-shortcut-after-a-skip rule.
- `app/Atelier/Sources/Atelier/Agent/AgentResponsesView.swift`: unchanged. Suspect 5 did not hold.

## Suspects

| Suspect | Holds | Note |
|---|---|---|
| 1 selected session never moves | Yes | `refresh` only picked when `selectedSession == nil`, and `selectedResponses` filters by it, so a new thread's answer never rendered. |
| 2 in-flight refresh dropped | Yes | `guard !isRefreshInFlight else { return }` with no retry; both scheduled tasks can land inside a parse. |
| 3 baseline latency | Not a defect | FSEvents 1.0 s plus a 400 ms debounce plus a 2 s discovery throttle. Debounce and throttle kept. Latency lowered to 0.3 s and CPU re-measured. |
| 4 byte-budget skip poisons the cache | Yes | The skipped file's fingerprint was stored, so the equality early return hid it until the file changed again. |
| 5 view follow-latest gate | No | `onChange(of: model.selectedResponses.last?.readIdentity)` advances when `selectedResponseID` equals the previous last (user on the newest) and holds when it does not (user navigated back). A session change is handled by `onChange(of: model.selectedSession) { selectLatestResponse() }`. No change made. |

## Contract

DESIGN.md `### Agent Responses` updated before the code change. The panel follows the newest session
until the user picks one, a refresh arriving during a refresh runs exactly once after it, a pass that
skipped a discovered file must not reuse the unchanged-fingerprint shortcut, and the watcher latency
is 0.3 seconds.

## Verified

1. `swift build --package-path app/Atelier` -> `ok (build complete)`.
2. `swift test --package-path app/Atelier` -> `Test run with 407 tests in 40 suites passed after
   3.726 seconds` (402 before this group's tests).
3. `app/Atelier/.build/debug/Atelier --selftest` -> `SELFTEST: ALL PASS`.
4. `Automatic session selection follows the newest session` passed. Session A then a newer session B
   ends with `selectedSession == B` and `selectedResponses == ["B one"]`.
5. `A hand-picked session stays selected when a newer session appears` passed. After
   `selectSession(A)`, a newer B leaves the selection on A; `selectSession(nil)` clears it.
6. `A refresh arriving during a refresh runs exactly one more pass` passed. `callCount` is 1 while
   the first load is suspended, 2 after the coalesced pass, and stays 2.
7. `Monitor retries a file the uncached byte budget skipped` passed. First pass `["Newer"]`, second
   pass `["Older", "Newer"]` with no file change in between, third pass reuses the shortcut
   (`mergeCount` unchanged).
8. `app/Atelier/scripts/build_and_run.sh run` -> SwiftLint gate passed, `Build complete! (11.44s)`,
   ad hoc signed, `satisfies its Designated Requirement`, app launched (pid 3632).
9. `app/Atelier/scripts/atelier-doctor status --json` -> `status healthy`, `snapshotAgeSeconds 0.704`,
   `workspace.active true`, `relativeRootName atelier`, `verdicts []`.
10. Not driven as a UI observation. No native UI automation is available in this environment and
    `atelier-doctor probe` has no response-overlay kind (`main`, `editor`, `editor-scroll`, `diff`
    only). Runtime evidence that the monitored path is live: the selected workspace starts monitoring
    at launch (`AppModel` passes `agentResponsesActive: state.id == selectedWorkspaceID`), and a live
    agent transcript inside the watched Claude root
    (`~/.claude/projects/-Users-hiep-Projects-atelier/<session>/subagents/workflows/<wf>/agent-*.jsonl`)
    was being appended during the measurement window (mtime matched wall clock). The refresh and
    selection behavior itself is covered by checks 4-7.
11. Idle CPU: `ps -p 3632 -o %cpu=` sampled 12 times at 5 s -> `0.0 0.0 0.4 0.0 0.2 0.0 0.3 0.0 0.5
    0.0 3.1 0.0`. Mean over a 60 s window from `cpuTimeSeconds` deltas: 0.0081 s / 60.00 s =
    **0.013 %**. Final snapshot `cpuPercent 0.080`, `heartbeatAgeMs 748`, `heartbeatPaused false`,
    `verdicts []`. Inside the 0.2-2 % bar with the 0.3 s watcher latency in place. No new `.ips`
    report in `~/Library/Logs/DiagnosticReports/`.
12. `detect_changes()` -> 5 changed files, exactly the expected ones. Affected processes are all in
    the transcript and response flow (`LoadResponsesWithoutInitialGate → *`, `Consume →
    StandardizedPath`, `ChooseWorkspace → Refresh`). No unrelated flow appeared. The reported
    `risk_level: high` is the count heuristic over 77 whole-file touched symbols, not a new
    cross-module edge.

## Notes

- Every existing performance guard is intact: fingerprint skip, discovery walk cache, newest-first
  stop, head probe, 1 MiB first-parse cap, 400 ms debounce, 3 s trailing refresh, 2 s discovery
  throttle.
- The coalesce keeps one pending pass at a time, never a queue.
