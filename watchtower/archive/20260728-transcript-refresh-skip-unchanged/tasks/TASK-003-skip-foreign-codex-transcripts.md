# TASK-003 Skip codex transcripts from other workspaces

Group: standalone

## Brief

Goal: stop the startup CPU burst. Read only the head of a transcript before its first parse. When
the head names another workspace, remember that answer and never read the rest of the file.

Change: a foreign codex session is parsed in full and then thrown away -> its head is read once, the
file is marked foreign, and later refreshes skip it without any read.

Evidence from TASK-002:

- The stop rule counts responses for this workspace only, so foreign sessions still get parsed while
  the restore looks for the newest 100 responses.
- Only 48 of the 100 newest codex files belong to this workspace. The other 52 hold about 190 MB.
- A 20 second `sample` at launch put 891 of 1024 monitor samples inside `AgentTranscriptParser.parse`.
- The cold start window still peaked at 93.0 percent for about 10 seconds.

How:

- Add a parser helper that returns the workspace path declared in a transcript head, for example
  `declaredWorkspacePath(_ jsonLines: String) -> String?`. Read the `session_meta` payload `cwd`
  first, then a top level `cwd`. Keep `AgentTranscriptParser.belongsToWorkspace` working by building
  it on the same helper, since
  [app/Atelier/Sources/Atelier/Terminal/MermaidFenceParser.swift](../../app/Atelier/Sources/Atelier/Terminal/MermaidFenceParser.swift)
  calls it.
- In `AgentTranscriptMonitor`, before the first parse of a file that has no cache entry, read only
  the head, for example the first 16 KiB, and ask for the declared workspace path.
- Mark the file foreign only when the head declares a different workspace. When the head declares
  nothing, parse the file as before. A missing answer must never drop a real transcript.
- Keep foreign URLs in a set beside `cache`, and drop entries the same way when discovery no longer
  lists a URL.
- Skip a known foreign URL before the attribute read, so a growing foreign session costs nothing.
- Do not count head bytes in `parsedByteCount`. That counter measures parsed transcript bytes.
- Update [DESIGN.md](../../DESIGN.md) first. State that a transcript whose head names another
  workspace is never parsed in full.

Files:

- [DESIGN.md](../../DESIGN.md) (add the foreign transcript rule beside the transcript refresh rules)
- [app/Atelier/Sources/Atelier/Agent/AgentResponses.swift](../../app/Atelier/Sources/Atelier/Agent/AgentResponses.swift)
  (`AgentTranscriptParser`: head helper; `AgentTranscriptMonitor`: head check and foreign set)
- [app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift](../../app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift)
  (add tests for the skip and for the unknown head case)

Expected result:

- A codex session from another workspace is never parsed in full.
- A transcript whose head declares no workspace is still parsed.
- The responses shown in the panel do not change.
- Idle CPU stays at or below 2 percent across a 5 minute window that starts right after launch,
  while an agent writes transcripts.

## Verify

- `swift build --package-path app/Atelier` -> `Build complete!`.
- `swift test --package-path app/Atelier` -> no new failure beyond the known flaky timing tests.
- `app/Atelier/.build/debug/Atelier --selftest` -> `SELFTEST: ALL PASS`.
- New test: one own transcript plus one large foreign transcript -> `parsedByteCount` counts only the
  own transcript, and the foreign file stays unparsed across two refreshes.
- New test: a transcript whose head declares no workspace -> still parsed.
- Existing tests `Monitor loads every matching transcript and deduplicates scans` and
  `Monitor stops reading older transcripts once the newest fill the limit` still pass.
- Relaunch with `app/Atelier/scripts/build_and_run.sh run`, then measure from a cold start while an
  agent writes transcripts. Revised bar (accepted 2026-07-29): while an agent produces a new
  response every 0.5 seconds, median at or below 2 percent, p90 at or below 5 percent, and no three
  consecutive samples above 10 percent. The strict idle rule (0.2 to 2 percent) applies only to windows
  with no new responses:

```bash
PID=$(pgrep -x Atelier | head -1)
top -l 150 -s 2 -pid $PID -stats pid,cpu | rg "^ *$PID" | awk '{print $2}' | sort -rn | head -5
```

- Confirm the response overlay still lists the same sessions after the change.
- Record median, p90, max, and the count of samples above 2 percent in the outcome sidecar.
