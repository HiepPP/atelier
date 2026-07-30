# Watchtower Next

## Current Active Plan

Title: Response panel question display and stale refresh fix
Slug: 20260730-response-panel-question-and-refresh
Status: ARCHIVED
Updated: 2026-07-30

The response overlay shows only the agent answer, and the user reports that it
sometimes lags behind or keeps showing an older response. Both TASKs work on
[app/Atelier/Sources/Atelier/Agent/AgentResponses.swift](app/Atelier/Sources/Atelier/Agent/AgentResponses.swift),
so they share one group and run in order.

## Tracker

| Order | TASK | Group | Status | Spec | Deps | Context | Notes |
|-------|------|-------|--------|------|------|---------|-------|
| 1 | TASK-001 | A | DONE | [watchtower/tasks/TASK-001-fix-stale-response-refresh.md](watchtower/tasks/TASK-001-fix-stale-response-refresh.md) | - | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Suspects 1, 2, and 4 held and were fixed. Suspect 3 was a latency budget, so the watcher latency moved from 1.0 to 0.3 seconds. Suspect 5 did not hold, so the view stayed unchanged. See [watchtower/tasks/TASK-001-outcome.md](watchtower/tasks/TASK-001-outcome.md). |
| 2 | TASK-002 | A | DONE | [watchtower/tasks/TASK-002-show-question-in-response-panel.md](watchtower/tasks/TASK-002-show-question-in-response-panel.md) | TASK-001 | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Added `AgentResponse.question`, the pending question in the parser state, the skip list, and `AgentResponseQuestionView`. Response ids did not change. See [watchtower/tasks/TASK-002-outcome.md](watchtower/tasks/TASK-002-outcome.md). |

## Plan Verify

- `swift build --package-path app/Atelier` passes with no warnings from changed files.
- `swift test --package-path app/Atelier` passes.
- `app/Atelier/.build/debug/Atelier --selftest` passes.
- `app/Atelier/scripts/build_and_run.sh run` builds, signs, installs, and opens the app.
- `app/Atelier/scripts/atelier-doctor status --json` reports `workspace.active` true before any
  runtime claim, and idle CPU stays in the 0.2-2 percent range while no agent writes.
- `DESIGN.md` and the shipped behavior agree after both TASKs.

## Handoff

Both TASKs shipped through one fan-out group: a builder, then a reviewer that returned `PASS`, so no
fixer pass ran. Plan Verify was re-run in the main session and passed: build ok, 407 tests in 40
suites pass, `SELFTEST: ALL PASS`, the app relaunched as pid 17896, `atelier-doctor` reports `status
healthy` with `workspace.active` true, and mean idle CPU over 60 seconds was 0.047 percent.

Two open items, both non-blocking:

- The on-screen checks were not driven: TASK-001 Verify step 10, and TASK-002 Verify steps 11 and 12.
  No native UI automation ran, and the repository forbids screenshots unless the user asks. Drive one
  pass with `Cmd-R` to confirm the `Question` label, the 3-line clamp, the disclosure toggle, the
  hover pointer cursor, and a card with no question.
- The reviewer flagged one edge in
  [app/Atelier/Sources/Atelier/Agent/AgentResponses.swift](app/Atelier/Sources/Atelier/Agent/AgentResponses.swift)
  near line 771. A transcript above `maximumTranscriptBytes` counts as a skipped file, so it keeps the
  unchanged-fingerprint shortcut off for up to 60 seconds. Optional fix: record a permanent size
  rejection in a skip set, like `foreignURLs`, instead of setting `skippedUncachedFile`.

Next action: drive the on-screen checks, then run `archive` for this plan.

## Archive

- Archived: 2026-07-30 -> watchtower/archive/20260730-response-panel-question-and-refresh/
