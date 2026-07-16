# NEXT

## Current Active Plan

- Title: Atelier MVP Milestones
- Slug: 20260716-atelier-mvp-milestones
- Status: ARCHIVED
- Updated: 2026-07-16

## Tracker

One row per milestone from [PLAN.md](PLAN.md). Each milestone ships on its own.

| Order | TASK | Group | Status | Spec | Deps | Context | Notes |
|-------|------|-------|--------|------|------|---------|-------|
| 1 | TASK-001 M0 app skeleton | M0 | DONE | [watchtower/tasks/TASK-001-m0-app-skeleton.md](watchtower/tasks/TASK-001-m0-app-skeleton.md) | - | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Built and verified. See outcome. |
| 2 | TASK-002 M1 file explorer + viewer | M1 | BLOCKED | [watchtower/tasks/TASK-002-m1-file-explorer.md](watchtower/tasks/TASK-002-m1-file-explorer.md) | TASK-001 | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Code and selftests pass. Computer Use authentication blocks native file-tree smoke. |
| 3 | TASK-003 M2 terminal multi-tab | M2 | BLOCKED | [watchtower/tasks/TASK-003-m2-terminal.md](watchtower/tasks/TASK-003-m2-terminal.md) | TASK-001 | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | SwiftTerm build passes. Computer Use authentication blocks two-tab smoke. |
| 4 | TASK-004 M3 git changes + diff | M3 | BLOCKED | [watchtower/tasks/TASK-004-m3-git-changes-diff.md](watchtower/tasks/TASK-004-m3-git-changes-diff.md) | TASK-001 | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Parser and runner selftests pass. Computer Use authentication blocks changes smoke. |
| 5 | TASK-005 M4 git basic ops | M4 | BLOCKED | [watchtower/tasks/TASK-005-m4-git-basic.md](watchtower/tasks/TASK-005-m4-git-basic.md) | TASK-004 | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Git action selftests pass. Computer Use authentication blocks commit flow. |
| 6 | TASK-006 M5 stability pass | M5 | BLOCKED | [watchtower/tasks/TASK-006-m5-stability.md](watchtower/tasks/TASK-006-m5-stability.md) | TASK-002, TASK-003, TASK-004, TASK-005 | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Signed `.app` and idle targets pass. Computer Use authentication blocks full GUI checks. |

TASK Status labels: TODO, IN PROGRESS, BLOCKED, DONE.
Plan-level Status header: ACTIVE while any row is open, DONE when all rows DONE, ARCHIVED after archive.

## Plan Verify

- cd [app/Atelier](app/Atelier) && swift build -> ok (build complete).
- .build/debug/Atelier --selftest -> SELFTEST: ALL PASS.
- Launch app, open a folder, run a CLI command, see a git change, commit from app.

## Handoff

- Next action: restore Computer Use host authentication, then run native GUI checks for TASK-002 through TASK-006 against [app/Atelier/dist/Atelier.app](app/Atelier/dist/Atelier.app).

## Archive

- Archived: 2026-07-16 -> watchtower/archive/20260716-atelier-mvp-milestones/
- None.
