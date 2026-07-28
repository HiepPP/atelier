# TASK-002 Outcome

## Outcome

Status: BLOCKED

## Changed

- `DESIGN.md`: added the rule that the source reads transcripts newest first and stops once it holds
  the newest 100 responses for the workspace, so older transcripts stay unread.
- `app/Atelier/Sources/Atelier/Agent/AgentResponses.swift`: the per-file loop in
  `loadResponsesWithoutInitialGate` now breaks as soon as `responses.count` reaches `responseLimit`.
  The check runs before the next file is opened, so an older transcript is never read.
- `app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift`: added
  `newestTranscriptsStopFurtherParsing`, which proves older files stay unparsed.

## Contract

- Discovery order stays newest first. The stop rule depends on it.
- The cache, the incremental append parse, the 16 MiB budget, the 100 file limit, and cancellation
  are unchanged.
- The published list still holds the newest responses for the workspace.

## Verified

- `swift build --package-path app/Atelier` -> `Build complete!`.
- `swift test --package-path app/Atelier` -> 322 tests in 28 suites. Only the known flaky
  `WorkspaceSearchTests.swift:653` failed on the final run.
- `app/Atelier/.build/debug/Atelier --selftest` -> `SELFTEST: ALL PASS`.
- New test `Monitor stops reading older transcripts once the newest fill the limit` -> passes.
  `parsedByteCount` equals the newest file size, so the two older files were never read.
- Existing test `Monitor restores only the newest 100 final responses` -> passes.
- `app/Atelier/scripts/build_and_run.sh run` -> built, signed, launched. No new Atelier report in
  `~/Library/Logs/DiagnosticReports/`.

Idle CPU with `top -l 150 -s 2`, 150 samples, measured while this agent session wrote transcripts:

| Window | Five highest | Median | p90 | Samples above 2 percent |
|--------|--------------|--------|-----|-------------------------|
| Warm process, TASK-001 only | 10.9, 8.1, 7.4, 7.2, 6.8 | 0.7 | 4.4 | 45 |
| Cold start, TASK-001 and TASK-002 | 93.0, 92.8, 83.4, 62.7, 51.6 | 0.6 | 2.4 | 18 |
| Same window, samples 16 to 150 | 3.7, 2.8, 2.4, 2.1, 1.9 | 0.6 | 1.3 | 4 |

## Blocked

The acceptance bar is not met. It asks for all five highest values at or below 2 percent across a
5 minute window that starts right after launch.

Steady state now passes: after the first 30 seconds, the highest value is 3.7 percent and only 4 of
135 samples sit above 2 percent. Samples above 2 percent fell from 45 to 4.

The startup restore still bursts. Samples 11 to 15 of the cold window hit 92.8, 83.4, and 93.0
percent, about 10 seconds of work. A 20 second `sample` started at launch names the owner:

```text
1024  AgentTranscriptMonitor.loadResponses()  AgentResponses.swift:490
 994  AgentTranscriptMonitor.loadResponsesWithoutInitialGate()  AgentResponses.swift:587
 891  AgentTranscriptParser.parse(data:workspacePath:sourceID:modifiedAfter:state:)
```

Cause: the stop rule counts responses for this workspace only. The newest files include codex
sessions from other workspaces, which produce no response, so the restore keeps parsing them until
100 workspace responses are in hand. Measured on this machine: only 48 of the 100 newest codex
files belong to this workspace, and the other 52 hold about 190 MB.

Next decision needed: whether to add a workspace prefilter. Read the head of each codex file, use
`AgentTranscriptParser.belongsToWorkspace` to test the `cwd`, cache the negative answer, and never
parse a foreign session in full. That removes the startup burst without changing what the panel
shows.
