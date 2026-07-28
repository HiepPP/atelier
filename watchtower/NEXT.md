# Watchtower Next

## Current Active Plan

Title: Transcript refresh skips unchanged files
Slug: 20260728-transcript-refresh-skip-unchanged
Status: ACTIVE
Updated: 2026-07-28

## Tracker

| Order | TASK | Group | Status | Spec | Deps | Context | Notes |
|-------|------|-------|--------|------|------|---------|-------|
| 1 | TASK-001 | standalone | DONE | [watchtower/tasks/TASK-001-skip-unchanged-transcripts.md](tasks/TASK-001-skip-unchanged-transcripts.md) | - | [watchtower/CONTEXT.md](CONTEXT.md) | Unchanged refresh now costs one stat per file |
| 2 | TASK-002 | standalone | DONE | [watchtower/tasks/TASK-002-stop-after-newest-responses.md](tasks/TASK-002-stop-after-newest-responses.md) | TASK-001 | [watchtower/CONTEXT.md](CONTEXT.md) | Newest-first stop shipped. CPU bar passed on to TASK-003 |
| 3 | TASK-003 | standalone | BLOCKED | [watchtower/tasks/TASK-003-skip-foreign-codex-transcripts.md](tasks/TASK-003-skip-foreign-codex-transcripts.md) | TASK-002 | [watchtower/CONTEXT.md](CONTEXT.md) | Foreign sessions skipped. First parse of a large own transcript still bursts |
| 4 | TASK-004 | standalone | BLOCKED | [watchtower/tasks/TASK-004-cap-first-parse-to-tail.md](tasks/TASK-004-cap-first-parse-to-tail.md) | TASK-003 | [watchtower/CONTEXT.md](CONTEXT.md) | Cap shipped. Steady state passes. First 95 seconds after a workspace opens still burst |
| 5 | TASK-005 | standalone | BLOCKED | [watchtower/tasks/TASK-005-three-day-history-window.md](tasks/TASK-005-three-day-history-window.md) | TASK-004 | [watchtower/CONTEXT.md](CONTEXT.md) | Three day window shipped. Restore is one 1.55 second pass. Bursts now belong to Git status |

## Plan Verify

- `swift build --package-path app/Atelier` passes.
- `swift test --package-path app/Atelier` shows no new failures against the three known flaky timing tests.
- `app/Atelier/.build/debug/Atelier --selftest` prints `SELFTEST: ALL PASS`.
- Idle CPU stays at or below 2 percent across a 5 minute window while an agent writes transcripts.

## Handoff

TASK-001 and TASK-002 are DONE. TASK-003 and TASK-004 shipped their code and tests, but the CPU bar
still fails during warmup, so both stay BLOCKED. Nothing is committed yet.

Four fixes shipped: unchanged refreshes cost one stat per file, the loop stops once the newest 100
responses are held, sessions from other workspaces are never parsed in full, and the first read of a
file above 1 MiB parses its header plus its newest 1 MiB. Steady state now sits at or below about
6 percent with a median of 0.5, and the parser no longer dominates a warm process.

TASK-005 shipped the three day window. The restore is now one pass of about 1.55 seconds, and the
next refresh parses nothing.

Next action: open a TASK against Git status refresh, then close TASK-003, TASK-004, and TASK-005
together. A 25 second sample during transcript writes ranks `GitOutputBox.capture` and
`GitCommand.run` at the top, and `AgentTranscriptMonitor` no longer appears in the top fourteen
frames. The transcript work in this plan is finished; the CPU bar now depends on a different
subsystem. See [watchtower/tasks/TASK-005-outcome.md](tasks/TASK-005-outcome.md) for the evidence.

## Archive

- Archived: 2026-07-28 -> [watchtower/archive/20260728-quick-open-external-paths-and-idle-cpu/](archive/20260728-quick-open-external-paths-and-idle-cpu/)
