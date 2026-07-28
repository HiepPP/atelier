# Watchtower Next

## Current Active Plan

Title: Quick Open external paths and idle CPU burst
Slug: 20260728-quick-open-external-paths-and-idle-cpu
Status: ARCHIVED
Updated: 2026-07-28

## Tracker

| Order | TASK | Group | Status | Spec | Deps | Context | Notes |
|-------|------|-------|--------|------|------|---------|-------|
| 1 | TASK-001 | A | DONE | [watchtower/tasks/TASK-001-quick-open-external-paths.md](tasks/TASK-001-quick-open-external-paths.md) | - | [watchtower/CONTEXT.md](CONTEXT.md) | Shipped. Reviewer verdict PASS |
| 2 | TASK-002 | B | DONE | [watchtower/tasks/TASK-002-idle-cpu-burst.md](tasks/TASK-002-idle-cpu-burst.md) | - | [watchtower/CONTEXT.md](CONTEXT.md) | Owner named. Peak idle CPU 71 to 7.1 percent. Residual recorded |

## Plan Verify

- `swift build --package-path app/Atelier` passes.
- `swift test --package-path app/Atelier` shows no new failures against the two known flaky tests.
- `app/Atelier/.build/debug/Atelier --selftest` prints `SELFTEST: ALL PASS`.

## Handoff

Both TASKs are DONE. Nothing is committed yet.

Next action: review the diff, then commit.

Open follow-up, not yet a TASK: the transcript refresh still re-walks directories and re-parses
files even when nothing changed. Idle CPU peaks at about 7 percent while an agent writes
transcripts, above the 2 percent rule. Skipping unchanged files by modification date and size
before parsing would remove most of the remaining work.

## Archive

- Archived: 2026-07-28 -> watchtower/archive/20260728-quick-open-external-paths-and-idle-cpu/
