# TASK-001 Stabilize Transcript Sessions

Group: A (response identity and session projection foundation)

## Brief

Goal: Produce stable, read-only response streams for concurrent Codex and Claude sessions. Repeated scans and appended transcript records must not create duplicate cards.

Change: File-level response polling -> deterministic provider and session projections.

How:

- Define a session key from provider and provider session ID.
- Prefer provider record IDs when building response IDs.
- Use a deterministic content digest when a transcript record has no ID.
- Keep response IDs stable across refreshes, file cache changes, and process restarts.
- Keep responses sorted by timestamp and deterministic identity.
- Expose session summaries with provider, session ID, latest response time, and unread count.
- Keep transcript discovery and loading read-only and off `MainActor`.
- Ignore malformed or incomplete JSONL records without dropping valid sessions.
- Cover concurrent sessions, repeated refreshes, appended records, and equal provider session IDs.

Files:

- [app/Atelier/Sources/Atelier/Agent/AgentResponses.swift](app/Atelier/Sources/Atelier/Agent/AgentResponses.swift) (stable response IDs, session keys, summaries, and snapshot merging)
- [app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift](app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift) (parser, monitor, deduplication, and multi-session tests)

Expected result:

- Codex and Claude sessions never merge when their raw session IDs match.
- Refreshing unchanged files adds no cards and changes no IDs.
- Appending a final answer preserves all earlier response IDs.
- One broken transcript does not block valid sessions.
- Monitoring never writes provider files or calls terminal APIs.

## Verify

- `swift test --package-path app/Atelier --filter AgentResponsesTests` -> all response identity and session tests pass.
- Run the same fixture scan twice -> response IDs and order remain equal.
- Append one final response to one of two fixture sessions -> only one new response appears.
- Search [app/Atelier/Sources/Atelier/Agent/AgentResponses.swift](app/Atelier/Sources/Atelier/Agent/AgentResponses.swift) for write APIs -> no transcript write path exists.
