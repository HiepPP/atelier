# TASK-002 Stop transcript parsing after the newest responses

Group: standalone

## Brief

Goal: stop parsing the whole transcript backlog. Discovery already sorts files newest first, so the
source can stop once it holds the newest 100 responses for the workspace. Older transcripts are then
never opened.

Change: every refresh walks all discovered files until the 16 MiB budget runs out -> the loop stops
as soon as the response limit is filled.

Measured evidence from TASK-001, taken on 2026-07-28:

- Candidate volume for this workspace: 384 MB across the 100 newest files in `~/.codex/sessions`,
  plus 76 MB across 49 files in the Claude project directory.
- Each refresh parses up to 16 MiB of not yet cached files, so the backlog needs about 30 refreshes
  to warm up, and each one is a CPU burst.
- A 30 second `sample` during a burst showed 1428 samples inside
  `AgentTranscriptMonitor.loadResponsesWithoutInitialGate` and 1262 of them inside
  `AgentTranscriptParser.parse`.
- First 5 minute window after launch: max 100.3 percent. Second window on the same warm process:
  max 10.9 percent, p90 4.4 percent, median 0.7 percent, 45 of 150 samples above 2 percent.
- Only 48 of the 100 newest codex files belong to this workspace, so half of that volume produces no
  response at all.

How:

- Stop the per-file loop in `loadResponsesWithoutInitialGate` once `responses.count` reaches
  `responseLimit`. Check before opening the next file, so the older file is never read.
- Keep the newest-first order from `transcriptURLs`. The stop rule depends on it.
- Keep the cache, the incremental append parse, the 16 MiB budget, and the cancellation checks.
- Keep the fingerprint skip from TASK-001 ahead of the loop.
- Update [DESIGN.md](../../DESIGN.md) first. State that the source reads transcripts newest first and
  stops once it holds the newest 100 responses, so older transcripts stay unread.

Files:

- [DESIGN.md](../../DESIGN.md) (add the newest-first stop rule beside the transcript refresh rules)
- [app/Atelier/Sources/Atelier/Agent/AgentResponses.swift](../../app/Atelier/Sources/Atelier/Agent/AgentResponses.swift)
  (`AgentTranscriptMonitor.loadResponsesWithoutInitialGate`: stop when the response limit is full)
- [app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift](../../app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift)
  (add a test that older transcripts stay unparsed)

Expected result:

- A workspace with a large transcript backlog parses only the newest files it needs.
- The newest responses still appear, and an append to the live transcript still shows up.
- Idle CPU stays at or below 2 percent across a 5 minute window that starts right after launch,
  while an agent writes transcripts.

## Verify

- `swift build --package-path app/Atelier` -> `Build complete!`.
- `swift test --package-path app/Atelier` -> no new failure beyond the known flaky timing tests.
- `app/Atelier/.build/debug/Atelier --selftest` -> `SELFTEST: ALL PASS`.
- New test: three transcripts with a small `responseLimit` -> `parsedByteCount` counts only the
  newest file, and the older files stay unparsed.
- Existing test `Monitor restores only the newest 100 final responses` still passes.
- Relaunch with `app/Atelier/scripts/build_and_run.sh run`, then measure from a cold start while an
  agent writes transcripts. All five highest values must be at or below 2 percent:

```bash
PID=$(pgrep -x Atelier | head -1)
top -l 150 -s 2 -pid $PID -stats pid,cpu | rg "^ *$PID" | awk '{print $2}' | sort -rn | head -5
```

- Record median, p90, max, and the count of samples above 2 percent in the outcome sidecar.
