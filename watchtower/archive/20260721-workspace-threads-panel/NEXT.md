# NEXT

## Current Active Plan

- Title: Workspace Threads Panel
- Slug: 20260721-workspace-threads-panel
- Status: ARCHIVED
- Updated: 2026-07-21

## Tracker

One row per TASK. Group ties together items that ship as one transaction.

| Order | TASK | Group | Status | Spec | Deps | Context | Notes |
|-------|------|-------|--------|------|------|---------|-------|
| 1 | TASK-001 Update DESIGN.md contract | A | DONE | [watchtower/tasks/TASK-001-design-contract.md](watchtower/tasks/TASK-001-design-contract.md) | - | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Contract updated for nested thread rows. |
| 2 | TASK-002 Agent detection service | B | DONE | [watchtower/tasks/TASK-002-agent-detection.md](watchtower/tasks/TASK-002-agent-detection.md) | TASK-001 | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Foreground process detection verified. |
| 3 | TASK-003 Threads panel model | B | DONE | [watchtower/tasks/TASK-003-threads-model.md](watchtower/tasks/TASK-003-threads-model.md) | TASK-002 | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Lifecycle and diffing verified. |
| 4 | TASK-004 Workspace group thread rows | B | DONE | [watchtower/tasks/TASK-004-threads-tab-ui.md](watchtower/tasks/TASK-004-threads-tab-ui.md) | TASK-003 | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Nested rows, exact selection, and focus verified. |

TASK Status labels: TODO, IN PROGRESS, BLOCKED, DONE.
Plan-level Status header: ACTIVE while any row is open, DONE when all rows DONE, ARCHIVED after archive.

## Plan Verify

- `swift build --package-path app/Atelier` -> builds with no error.
- `swift test --package-path app/Atelier` -> all tests pass, including new detection tests.
- `app/Atelier/.build/debug/Atelier --selftest` -> self-test passes.
- UI smoke: open two workspaces and run `claude` in one terminal. Its nested row shows running. When the agent exits, the row shows done. Closing the terminal removes the row. Clicking a workspace header activates its project. Clicking a thread activates its project, selects the exact terminal, and focuses input. Idle CPU stays in the 0.2-2% range while the app is idle.

## Handoff

- Implementation complete. All TASK outcomes and Plan Verify checks passed.
- No commit or push was requested.

## Archive

- Archived: 2026-07-21 -> watchtower/archive/20260721-workspace-threads-panel/
