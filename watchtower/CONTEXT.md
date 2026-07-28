# Watchtower Context

Shared context for the active plan. Read this before any TASK in [watchtower/NEXT.md](NEXT.md).

## Repository Rules

- Read [DESIGN.md](../DESIGN.md) before changing code. Update it first when a TASK changes the contract.
- Invoke `$swiftui-expert-skill` before writing, editing, or reviewing Swift code.
- Run GitNexus `impact` before editing a symbol, and `detect_changes` before committing.
- Never reload or invalidate after a refresh that produced no change.
- Keep the simplest structure that gives the required behavior.

## What Already Shipped

The archived plan [watchtower/archive/20260728-quick-open-external-paths-and-idle-cpu/](archive/20260728-quick-open-external-paths-and-idle-cpu/)
found the owner of the idle CPU burst and cut peak idle CPU from 71 percent to 7.1 percent.

- A running agent writes its own transcript, so the watcher emits a steady event stream.
- `AgentResponsesModel.handleWatcherEvent` now debounces that burst into one refresh after 400 milliseconds of quiet.
- A 3 second trailing refresh still covers files created inside the discovery throttle window.
- The residual cost is the debounced refresh itself. It still walks directories, stats every file, and rebuilds the merged response list even when no transcript changed.

## Source Anchors

All in [app/Atelier/Sources/Atelier/Agent/AgentResponses.swift](../app/Atelier/Sources/Atelier/Agent/AgentResponses.swift):

- `AgentTranscriptMonitor.loadResponsesWithoutInitialGate` at line 486: the refresh body that stats, parses, merges, and sorts.
- `AgentTranscriptMonitor.transcriptURLs` at line 591 and `collectRecentTranscriptEntries` at line 614: the directory walk. It already reads modification date and file size into `TranscriptEntry`.
- `CachedTranscript` at line 401: the per-file cache, keyed by size and file ID.
- `AgentResponsesModel.refresh` at line 860: it already skips state changes when no new response arrives.

## Verification Bias

Run these from the repository root:

```bash
swift build --package-path app/Atelier
swift test --package-path app/Atelier
app/Atelier/.build/debug/Atelier --selftest
app/Atelier/scripts/build_and_run.sh run
```

Three tests already fail on a clean tree. They are timing tests, not regressions:

- `PrecommitWhisperTests.swift:121-123`
- `WorkspaceToolExecutorTests.swift:90` "In-flight search stops when its owner is cancelled"
- `WorkspaceSearchTests.swift:653` "New typing cancels a running stale search"

Treat only new failures as regressions.

## Performance Baseline

The repository rule is 0.2 to 2 percent CPU at idle. Measure over a full 5 minute window. A short
window misses the burst and reports a false pass. Measure while an agent session writes transcripts,
because that is the worst case for this path.

```bash
PID=$(pgrep -x Atelier | head -1)
top -l 150 -s 2 -pid $PID -stats pid,cpu | rg "^ *$PID" | awk '{print $2}' | sort -rn | head -5
```

Last recorded result on the shipped build: median 0.7 percent, p90 1.2 percent, max 7.1 percent
across 150 samples.

## Decisions

- Keep the 400 millisecond debounce and the 3 second trailing refresh. This plan cuts the cost of one refresh, not the refresh rate.

## Open Decisions

- None.
