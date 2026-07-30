# TASK-001 Fix the stale and lagging response panel

Group: A

## Brief

Goal: Make the response panel always show the newest final response for the workspace. Confirm each
suspect below against the source first, then fix only the ones that hold.

The user reports two symptoms: the panel does not refresh to the latest response, and it sometimes
lags behind. Code reading found five suspects. Suspects 1, 2, and 4 look like real defects. Suspect 3
is a latency budget, not a defect. Suspect 5 needs a check and may be fine.

Change: coalesce a refresh that arrives while one is in flight, follow the newest session, and stop
the fingerprint cache from hiding a file the byte budget skipped.

### Suspect 1: the selected session never moves

`AgentResponsesModel.refresh` picks a session only when none is picked:

```swift
if selectedSession == nil {
    selectedSession = sessionSummaries.first?.session
}
```

`selectedResponses` filters by `selectedSession`, and the panel renders only `selectedResponses`.
When the user starts a new agent thread, the new responses land in a new session, and the panel keeps
rendering the old one. The response arrived, but the user never sees it. This matches "does not show
the latest response" exactly.

Fix: follow the newest session while the user has not chosen one by hand. Track whether the user
picked the session through `selectSession`. When the pick is automatic, move it to
`sessionSummaries.first?.session` on every refresh that adds responses. When the user picked it, keep
it. Also keep a session pinned once it is chosen even if a newer one appears.

### Suspect 2: a refresh that arrives during a refresh is dropped and never retried

`AgentResponsesModel.refresh` starts with:

```swift
guard !isRefreshInFlight else { return }
```

Nothing reschedules the dropped call. `handleWatcherEvent` schedules a debounced refresh at 400 ms
and a trailing refresh at 3 s, and it cancels and reschedules both on each event. When a refresh is
still parsing, either of those can hit the guard and vanish. The panel then waits for the next
filesystem event. If the dropped call was the one covering the final answer, and the agent has
stopped writing, no further event arrives and the panel stays stale until the user clicks Refresh.

Fix: replace the drop with a coalesce. Set a `needsAnotherRefresh` flag when a call finds a refresh in
flight, and run exactly one more refresh after the current one finishes. Keep only one extra pass, not
a queue, so a burst still collapses.

### Suspect 3: baseline latency, expected not broken

Three delays stack before a new response can appear:

- `FSEventStreamCreate` uses a `1.0` second latency.
- `handleWatcherEvent` waits 400 ms to collapse the burst.
- `AgentTranscriptMonitor` throttles discovery with `discoveryInterval: 2`.

So over one second of lag is by design, and the discovery throttle can add more for a brand-new
transcript file. Do not remove the debounce or the discovery throttle: they exist to hold idle CPU
inside the 0.2-2 percent bar. Lower the FSEvents latency from `1.0` to `0.3` only if the CPU check in
`## Verify` still passes. Report the measured numbers either way.

### Suspect 4: a byte-budget skip poisons the unchanged-fingerprint cache

Inside `loadResponsesWithoutInitialGate`:

```swift
guard uncachedBytes <= remainingUncachedBytes else {
    continue
}
```

That `continue` skips the file without writing `cache[url]`. Later the same pass stores the full list:

```swift
lastFingerprints = fingerprints
```

The skipped file is in `fingerprints`. On the next refresh, if nothing changed, the early return fires:

```swift
if hasMergedResult, fingerprints == lastFingerprints {
    return lastMergedResponses
}
```

So the skipped file's responses never appear until that file changes again. Same hole applies to the
`continue` paths above it that skip a file without caching it.

Fix: when a pass skips a discovered file without caching it, do not record the unchanged-fingerprint
shortcut for the next pass. Set `hasMergedResult = false` for that pass, or drop the skipped files
from `lastFingerprints`, so the next refresh retries them.

### Suspect 5: the view follow-latest gate, check only

`AgentResponsesView` advances the shown card only under a condition:

```swift
.onChange(of: model.selectedResponses.last?.readIdentity) { previous, current in
    if selectedResponseID == nil || selectedResponseID == previous {
        selectedResponseID = current
    }
}
```

`selectedResponseIndex` falls back to `model.selectedResponses.count - 1` when the stored id matches
nothing, so this looks self-healing. Confirm that a new response in the currently selected session
does move the card while the user sits on the newest one, and does not move it while the user has
navigated back. Change nothing if it already behaves that way.

How:

- Run `impact({target: "refresh", direction: "upstream"})` and `impact({target: "loadResponses", direction: "upstream"})`
  before editing. Report the blast radius. Warn before proceeding on HIGH or CRITICAL risk.
- Read the whole of [app/Atelier/Sources/Atelier/Agent/AgentResponses.swift](app/Atelier/Sources/Atelier/Agent/AgentResponses.swift)
  and the `### Agent Responses` section of [DESIGN.md](DESIGN.md) first.
- Confirm each suspect in the source. Write down which ones hold and which do not.
- Update [DESIGN.md](DESIGN.md) before the code change: state that the panel follows the newest
  session until the user picks one, that a refresh arriving during a refresh runs once after it, and
  that a pass which skips a discovered file must not reuse the unchanged-fingerprint shortcut.
- Fix the confirmed suspects. Keep each fix small and inside the existing types.
- Add deterministic tests to [app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift](app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift).
- Run `detect_changes()` at the end.

Files:

- [app/Atelier/Sources/Atelier/Agent/AgentResponses.swift](app/Atelier/Sources/Atelier/Agent/AgentResponses.swift):
  coalesce the in-flight refresh, follow the newest session, repair the fingerprint shortcut, and
  optionally lower the FSEvents latency.
- [app/Atelier/Sources/Atelier/Agent/AgentResponsesView.swift](app/Atelier/Sources/Atelier/Agent/AgentResponsesView.swift):
  change only if suspect 5 turns out to be real.
- [app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift](app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift):
  add one test per confirmed fix.
- [DESIGN.md](DESIGN.md): update the `### Agent Responses` contract.

Expected result:

- A response written into a brand-new session shows in the panel without the user opening the picker.
- A session the user picked by hand stays picked when a newer session appears.
- A refresh that arrives while one is in flight causes exactly one more refresh, not zero and not a
  queue of them.
- A refresh pass that skipped a discovered file retries that file on the next pass.
- Idle CPU stays in the 0.2-2 percent range with no agent writing.

Prompt:

```text
Invoke $swiftui-expert-skill. Read app/Atelier/Sources/Atelier/Agent/AgentResponses.swift in full
and the "### Agent Responses" section of DESIGN.md. Then confirm the five suspects in
watchtower/tasks/TASK-001-fix-stale-response-refresh.md against the source, one at a time, and say
which hold. Update DESIGN.md first, then fix only the confirmed suspects. Keep every existing
performance guard: the fingerprint skip, the discovery walk cache, the newest-first stop, the head
probe, and the 1 MiB first-parse cap. Add deterministic tests in
app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift. Use /solve if a suspect does not reproduce
and the real cause is still unknown.
```

## Verify

1. `swift build --package-path app/Atelier` -> succeeds.
2. `swift test --package-path app/Atelier` -> all tests pass, including the new ones.
3. `app/Atelier/.build/debug/Atelier --selftest` -> passes.
4. New test: a model whose source returns a response in session A, then a newer response in session
   B, ends with `selectedSession` equal to session B, and `selectedResponses` holds the session B
   response.
5. New test: after `selectSession` picks session A by hand, a newer session B response leaves
   `selectedSession` on session A.
6. New test: two refreshes started back to back, where the source is slow, call
   `loadResponses` twice, not once and not three times.
7. New test: a monitor whose `uncachedBytesLimit` forces a skip of one discovered file returns that
   file's responses on the next `loadResponses` call, with no change to any file in between.
8. `app/Atelier/scripts/build_and_run.sh run` -> builds, signs, installs, and opens the app.
9. `app/Atelier/scripts/atelier-doctor status --json` -> `status` is `healthy` and
   `workspace.active` is true. Record the value before any CPU claim.
10. Run one agent turn in the terminal, wait for its final answer, and confirm the panel shows that
    answer with no manual Refresh click. Record the wall-clock delay between the answer landing in
    the terminal and the card appearing.
11. `ps -p <PID> -o %cpu=` with no agent writing -> idle CPU inside 0.2-2 percent.
12. `detect_changes()` -> only the expected symbols and flows changed.
