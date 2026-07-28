# TASK-001 Skip unchanged transcript files before parsing

Group: standalone

## Brief

Goal: make a transcript refresh cost almost nothing when no transcript file changed. Skip unchanged
files by modification date and size before any parse or merge, so idle CPU stays at or below
2 percent while an agent writes transcripts.

Change: every debounced refresh stats each file again, re-copies every cached response, and rebuilds
the merged list -> a refresh with no file change returns the previous result and touches nothing.

Where the residual work happens today, in
[app/Atelier/Sources/Atelier/Agent/AgentResponses.swift](../../app/Atelier/Sources/Atelier/Agent/AgentResponses.swift):

- `loadResponsesWithoutInitialGate` calls `FileManager.attributesOfItem` for every discovered file on
  every refresh, even when the file is cached and unchanged.
- The walk in `collectRecentTranscriptEntries` already read modification date and size into
  `TranscriptEntry`, so that second stat repeats work the walk just did.
- Even when every file hits the cache, the method still appends all cached responses, builds a
  dictionary of up to 100 responses per file, sorts them, and returns a fresh array.
- A file that grows is parsed from its previous offset only, so incremental parsing is already
  correct. Leave it as is.

How:

- Keep the discovered walk results as `TranscriptEntry` values, not bare URLs, so modification date
  and size from the walk stay available.
- Build one cheap fingerprint per refresh: the ordered list of file URL, size, and modification date.
- Return the stored merged result right away when the fingerprint matches the previous refresh. Do
  not stat, parse, merge, or sort in that case.
- When the fingerprint differs, run the existing loop, but stat with `attributesOfItem` only for
  files whose size or modification date changed. Reuse the cached responses for the rest.
- Store the merged result and the fingerprint at the end of a full refresh.
- Add a counter that increments only when a full merge runs, so a test can prove the skip.
- Keep the parse path, the 16 MiB uncached byte limit, the 100 file limit, and cancellation checks
  unchanged.
- Measure first with the 5 minute window in [watchtower/CONTEXT.md](../CONTEXT.md). If idle CPU is
  still above 2 percent after the skip, the next suspect is the directory walk that runs every
  2 seconds through `nextDiscoveryDate`. Only then change the walk, and record why.
- Update [DESIGN.md](../../DESIGN.md) near line 1074, next to the existing transcript debounce rule,
  before editing code. State that a refresh with no changed transcript file must not parse, merge, or
  publish anything.

Files:

- [DESIGN.md](../../DESIGN.md) (add the unchanged-refresh rule beside the transcript debounce rule)
- [app/Atelier/Sources/Atelier/Agent/AgentResponses.swift](../../app/Atelier/Sources/Atelier/Agent/AgentResponses.swift)
  (`AgentTranscriptMonitor`: keep walk metadata, add the fingerprint skip, add the merge counter)
- [app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift](../../app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift)
  (add tests for the skip and for a real append)

Expected result:

- Two `loadResponses()` calls with no file change return the same responses, and the second one does
  no parse and no merge.
- An appended transcript still shows its new responses after the next refresh.
- A new transcript file still appears after the next discovery pass.
- Idle CPU stays at or below 2 percent across a 5 minute window while an agent writes transcripts.

Prompt:

```text
Cut the residual idle CPU in Atelier transcript refresh. Skip unchanged transcript files by
modification date and size before parsing, and return the stored merged result when no file
changed. Invoke $swiftui-expert-skill first. Run GitNexus impact on
loadResponsesWithoutInitialGate and transcriptURLs before editing. Update DESIGN.md first.
Measure idle CPU with the full 5 minute top window while an agent writes transcripts, not a
short window.
```

## Verify

- `swift build --package-path app/Atelier` -> `Build complete!`.
- `swift test --package-path app/Atelier` -> no new failure beyond the three known flaky timing tests.
- `app/Atelier/.build/debug/Atelier --selftest` -> `SELFTEST: ALL PASS`.
- New test: two `loadResponses()` calls on an unchanged transcript directory -> equal response ids,
  `parsedByteCount` unchanged, and the merge counter unchanged after the second call.
- New test: append one entry to a transcript file, then refresh -> the new response appears and
  `parsedByteCount` grows by the appended bytes only.
- Launch with `app/Atelier/scripts/build_and_run.sh run`, keep an agent session writing transcripts,
  then record the five highest values. All five must be at or below 2 percent:

```bash
PID=$(pgrep -x Atelier | head -1)
top -l 150 -s 2 -pid $PID -stats pid,cpu | rg "^ *$PID" | awk '{print $2}' | sort -rn | head -5
```

- Record the measured median, p90, and max in the outcome sidecar, with the sample count.
- `sample` during a burst -> `AgentTranscriptParser.parse` no longer repeats when no file changed.
