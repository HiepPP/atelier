# TASK-001 Outcome

## Outcome

Status: DONE

## Changed

- `DESIGN.md`: added the rule that a refresh with no changed transcript file reads no full file
  attributes, parses nothing, rebuilds no list, and publishes no state change.
- `app/Atelier/Sources/Atelier/Agent/AgentResponses.swift`: `AgentTranscriptMonitor` now fingerprints
  every discovered file with one `stat` call per refresh. When the fingerprint list matches the
  previous refresh, the stored merged result is returned at once. When one file changed, only that
  file takes the full attribute read and the parse path; the rest reuse their cached responses.
- `app/Atelier/Sources/Atelier/Agent/AgentResponses.swift`: the per-file cache now stores the
  modification date from the same `stat` source, so both refreshes compare dates read the same way.
- `app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift`: added
  `unchangedTranscriptRefreshSkipsWork`, which proves the skip through a new `mergeCount` counter.

## Contract

- A refresh where no transcript file changed returns the previous merged list and does no other work.
- A refresh where one file changed still parses only the appended bytes of that file.
- The 16 MiB uncached byte limit, the 100 file limit, the response limit, and cancellation are
  unchanged.

## Verified

- `swift build --package-path app/Atelier` -> `Build complete!`.
- `swift test --package-path app/Atelier` -> 322 tests in 28 suites. Only the known flaky timing
  tests failed: `PrecommitWhisperTests.swift:121-123` and `WorkspaceSearchTests.swift:653`.
- `app/Atelier/.build/debug/Atelier --selftest` -> `SELFTEST: ALL PASS`.
- New test `Monitor skips the merge when no transcript file changed` -> passes. Second refresh keeps
  `mergeCount` and `parsedByteCount` unchanged; the later append raises both.
- Existing test `Monitor parses only appended transcript bytes` -> passes.
- GitNexus `impact`: `loadResponsesWithoutInitialGate` LOW, 3 impacted; `transcriptURLs` LOW,
  4 impacted. Both are private and only reached through `loadResponses`.

## Notes

The first attempt used `url.resourceValues(forKeys:)` for the fingerprint. URL resource values are
cached on the URL, so an appended file kept reporting its old size and two tests failed. The fix
reads `stat` directly, which is also the cheaper call.

The CPU bar in this TASK was not met by this change alone. A 5 minute window after launch still
peaked at 100.3 percent, and a warm window peaked at 10.9 percent with 45 of 150 samples above
2 percent. A 30 second `sample` named the owner: first-time parsing of a large transcript backlog
inside `AgentTranscriptParser.parse`. That work belongs to
[watchtower/tasks/TASK-002-stop-after-newest-responses.md](TASK-002-stop-after-newest-responses.md),
which owns the final CPU measurement.
