# TASK-001 Outcome

## Outcome

Status: DONE

Changed:
- Added provider-scoped `AgentSessionIdentity` values for Codex and Claude.
- Replaced path-and-order response IDs with session and record identities.
- Added deterministic FNV-1a fallbacks when transcripts omit session or record IDs.
- Added session summaries with latest time, response count, unread count, and stable selection.

Contract:
- Explicit provider session IDs remain stable when transcript files move.
- Missing IDs remain deterministic for one provider, workspace, and transcript source.
- Equal raw response IDs from different providers remain distinct.
- Opening the preview does not clear unread responses from hidden sessions.

Verified:
- `swift test --package-path app/Atelier` passed all 65 tests.
- Session selection, unread scoping, multi-session discovery, and repeat-scan deduplication tests passed.
- Live Codex and Claude transcripts appeared as separate provider-scoped preview sessions.
- `app/Atelier/.build/debug/Atelier --selftest` passed all checks.
