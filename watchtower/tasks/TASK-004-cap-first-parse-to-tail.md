# TASK-004 Cap the first parse of a large transcript to its tail

Group: standalone

## Brief

Goal: stop the last CPU burst. On the first read of a transcript above 1 MiB, parse only its head
plus its newest 1 MiB. Small files stay whole.

Change: the first read of an 8 MB transcript parses all 8 MB -> it parses the session header plus the
last 1 MiB.

Evidence from TASK-003:

- Own transcripts for this workspace reach 8.3 MB, 7.7 MB, and 5.0 MB.
- When such a file becomes the newest one, it is read from byte zero, which costs about 10 seconds of
  CPU near 90 percent.
- The panel restores only the newest 100 responses, so the older part of that file cannot appear.

The head still matters. `AgentTranscriptParser.consume` only accepts a codex response when
`state.codexWorkspace` matches, and that value comes from the `session_meta` line at the top of the
file. A tail-only read would drop every codex response, so the head must stay in the parsed buffer.

How:

- Add a first-parse cap, for example `maximumFirstParseBytes = 1 MiB`.
- Keep the current behavior for a file at or below the cap, and for every append read.
- For a first read above the cap, build the parse buffer from two pieces:
  - The head already used for the workspace probe, cut at its last newline so no partial line enters.
  - The last 1 MiB, started at its first complete line.
- Parse the joined buffer once.
- Store the true end offset in the cache, not the number of parsed bytes, so a later append still
  reads from the real end of the file.
- Count only parsed bytes in `parsedByteCount`.
- Update [DESIGN.md](../../DESIGN.md) first. State that a transcript above 1 MiB restores its session
  header and its newest 1 MiB only, and that older responses inside that file are not restored.

Files:

- [DESIGN.md](../../DESIGN.md) (state the restore contract change for large transcripts)
- [app/Atelier/Sources/Atelier/Agent/AgentResponses.swift](../../app/Atelier/Sources/Atelier/Agent/AgentResponses.swift)
  (`AgentTranscriptMonitor`: first-parse cap, head plus tail buffer, true end offset in the cache)
- [app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift](../../app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift)
  (add tests for the cap, for a codex file above the cap, and for an append after a capped read)

Expected result:

- A first read of a transcript above 1 MiB parses close to 1 MiB, not the whole file.
- A codex transcript above the cap still shows its newest responses, because the header is kept.
- An append to a capped file still adds only the appended bytes.
- Small transcripts keep their current behavior.
- Idle CPU stays at or below 2 percent across a 5 minute window that starts right after launch,
  while an agent writes transcripts.

## Verify

- `swift build --package-path app/Atelier` -> `Build complete!`.
- `swift test --package-path app/Atelier` -> no new failure beyond the known flaky timing tests.
- `app/Atelier/.build/debug/Atelier --selftest` -> `SELFTEST: ALL PASS`.
- New test: a codex transcript above 1 MiB -> the newest response appears, the oldest one does not,
  and `parsedByteCount` stays near 1 MiB.
- New test: append to that file after the capped read -> `parsedByteCount` grows by the appended
  bytes only, and the new response appears.
- Existing tests `Monitor loads every matching transcript and deduplicates scans`,
  `Monitor restores only the newest 100 final responses`, and
  `Monitor parses only appended transcript bytes` still pass.
- Relaunch with `app/Atelier/scripts/build_and_run.sh run`, then measure from a cold start while an
  agent writes transcripts. All five highest values must be at or below 2 percent:

```bash
PID=$(pgrep -x Atelier | head -1)
top -l 150 -s 2 -pid $PID -stats pid,cpu | rg "^ *$PID" | awk '{print $2}' | sort -rn | head -5
```

- Drive real transcript writes during the window. A quiet window proves nothing here.
- Open the response overlay and confirm the newest sessions still appear.
- Record median, p90, max, and the count of samples above 2 percent in the outcome sidecar.
