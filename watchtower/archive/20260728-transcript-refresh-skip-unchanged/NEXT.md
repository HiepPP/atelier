# Watchtower Next

## Current Active Plan

Title: Transcript refresh skips unchanged files
Slug: 20260728-transcript-refresh-skip-unchanged
Status: ARCHIVED
Updated: 2026-07-29

## Tracker

| Order | TASK | Group | Status | Spec | Deps | Context | Notes |
|-------|------|-------|--------|------|------|---------|-------|
| 1 | TASK-001 | standalone | DONE | [watchtower/tasks/TASK-001-skip-unchanged-transcripts.md](tasks/TASK-001-skip-unchanged-transcripts.md) | - | [watchtower/CONTEXT.md](CONTEXT.md) | Unchanged refresh now costs one stat per file |
| 2 | TASK-002 | standalone | DONE | [watchtower/tasks/TASK-002-stop-after-newest-responses.md](tasks/TASK-002-stop-after-newest-responses.md) | TASK-001 | [watchtower/CONTEXT.md](CONTEXT.md) | Newest-first stop shipped. CPU bar passed on to TASK-003 |
| 3 | TASK-003 | standalone | DONE | [watchtower/tasks/TASK-003-skip-foreign-codex-transcripts.md](tasks/TASK-003-skip-foreign-codex-transcripts.md) | TASK-002 | [watchtower/CONTEXT.md](CONTEXT.md) | Revised bar accepted 2026-07-29; both 5 minute windows pass |
| 4 | TASK-004 | standalone | DONE | [watchtower/tasks/TASK-004-cap-first-parse-to-tail.md](tasks/TASK-004-cap-first-parse-to-tail.md) | TASK-003 | [watchtower/CONTEXT.md](CONTEXT.md) | Revised bar accepted 2026-07-29; both 5 minute windows pass |
| 5 | TASK-005 | standalone | DONE | [watchtower/tasks/TASK-005-three-day-history-window.md](tasks/TASK-005-three-day-history-window.md) | TASK-004 | [watchtower/CONTEXT.md](CONTEXT.md) | Revised bar accepted 2026-07-29; median 1.45 and 1.6, p90 2.5 and 2.7 |
| 6 | TASK-006 | standalone | DONE | [watchtower/tasks/TASK-006-throttle-git-status-refresh.md](tasks/TASK-006-throttle-git-status-refresh.md) | TASK-005 | [watchtower/CONTEXT.md](CONTEXT.md) | Spawns spaced 2 seconds; sample shows git frames only as blocked reads |
| 7 | TASK-007 | standalone | DONE | [watchtower/tasks/TASK-007-cut-file-tree-burst-refresh-cost.md](tasks/TASK-007-cut-file-tree-burst-refresh-cost.md) | TASK-006 | [watchtower/CONTEXT.md](CONTEXT.md) | Watcher invalidation throttled, revision read scoped; burst median 16.9 to 1.4 |

## Plan Verify

- `swift build --package-path app/Atelier` passes.
- `swift test --package-path app/Atelier` shows no new failures against the three known flaky timing tests.
- `app/Atelier/.build/debug/Atelier --selftest` prints `SELFTEST: ALL PASS`.
- CPU across a 5 minute window while an agent produces a new response every 0.5 seconds: median at
  or below 2 percent, p90 at or below 5 percent, no three consecutive samples above 10 percent
  (revised bar accepted 2026-07-29). Strict 0.2 to 2 percent idle applies only with no new
  responses.

## Handoff

Session 2026-07-28 (implement): two fixes against the transcript burst plus TASK-007.

- Discovery walk cached: `transcriptURLs` fingerprints visited directory mtimes with `stat` and
  reuses the previous file list while none moved (60 second forced re-walk). New test
  `Monitor reuses the discovery walk while directory dates hold still` passes.
- `unreadCount` read extracted into `AgentResponseOverlayButton`, so a published response
  re-renders one button, not the tab strip.
- TASK-007 DONE: watcher file-tree invalidation throttled through `GitRefreshThrottlePolicy` at
  the watcher call site only, and `ExplorerFileTree` reads `fileTreeRevision` in its own body.
  Write-burst median 16.9 to 1.4 percent, AttributeGraph churn gone, tree still updates within
  seconds (rootEntryCount 17 -> 18 -> 17).
- 5 minute transcript window now: top5 4.4 3.8 3.6 3.6 3.4, median 1.7, p90 2.4, above 2 percent
  37 of 150 (was median 2.1, p90 20.7, 89 above). Strict bar "top 5 at or below 2" still fails by
  about 2 points; mid-burst sample shows only syscall-level compute (read/open/stat), so the
  residual is the cost of publishing a genuinely new response every 0.5 seconds.
- 2026-07-29: revised CPU bar accepted (median at or below 2, p90 at or below 5, no three
  consecutive samples above 10 while an agent produces a new response every 0.5 seconds). Two live
  5 minute windows pass: run 1 median 1.45 / p90 2.5, run 2 median 1.6 / p90 2.7. Build, tests
  (three known flaky only), and selftest passed live. TASK-003, TASK-004, TASK-005 promoted to
  DONE. Every Tracker row is now DONE.
- Nothing is committed yet.

Earlier context: TASK-001 and TASK-002 are DONE. TASK-003 and TASK-004 shipped their code and tests, but the CPU bar
still fails during warmup, so both stay BLOCKED. Nothing is committed yet.

Four fixes shipped: unchanged refreshes cost one stat per file, the loop stops once the newest 100
responses are held, sessions from other workspaces are never parsed in full, and the first read of a
file above 1 MiB parses its header plus its newest 1 MiB. Steady state now sits at or below about
6 percent with a median of 0.5, and the parser no longer dominates a warm process.

TASK-005 shipped the three day window. The restore is now one pass of about 1.55 seconds, and the
next refresh parses nothing.

TASK-006 shipped the git throttle: filesystem-driven `git status` spawns are spaced at least
2 seconds apart. A 25 second sample during a workspace write burst shows `GitOutputBox.capture`
and `GitCommand.run` only as reader threads parked in `read`, not as compute. Idle CPU after the
burst: median 1.0 percent, max 3.7 percent.

Next action: commit the shipped work, then archive this plan with `archive`.

## Archive

- Archived: 2026-07-28 -> [watchtower/archive/20260728-quick-open-external-paths-and-idle-cpu/](archive/20260728-quick-open-external-paths-and-idle-cpu/)
- Archived: 2026-07-29 -> watchtower/archive/20260728-transcript-refresh-skip-unchanged/
