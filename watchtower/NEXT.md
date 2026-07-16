# NEXT

## Current Active Plan

- Title: Atelier Minimal Luminare Integration
- Slug: 20260716-atelier-minimal-luminare-integration
- Status: ACTIVE
- Updated: 2026-07-16

## Tracker

One row per task. Each task keeps the current three-column product contract.

| Order | TASK | Group | Status | Spec | Deps | Context | Notes |
|-------|------|-------|--------|------|------|---------|-------|
| 1 | TASK-001 Luminare compatibility gate | A | DONE | [watchtower/tasks/TASK-001-luminare-compatibility-gate.md](watchtower/tasks/TASK-001-luminare-compatibility-gate.md) | - | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Vendored 0.2.0 resolves with Introspect 26.0.1. |
| 2 | TASK-002 Add the theme adapter | A | DONE | [watchtower/tasks/TASK-002-add-theme-adapter.md](watchtower/tasks/TASK-002-add-theme-adapter.md) | TASK-001 | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | App-owned adapter preserves package boundary. |
| 3 | TASK-003 Migrate existing buttons | B | BLOCKED | [watchtower/tasks/TASK-003-migrate-existing-buttons.md](watchtower/tasks/TASK-003-migrate-existing-buttons.md) | TASK-002 | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Code passes; reload, shortcut, hover, pressed, and focus proof remains. |
| 4 | TASK-004 Polish status and inspector surfaces | C | BLOCKED | [watchtower/tasks/TASK-004-polish-status-inspector.md](watchtower/tasks/TASK-004-polish-status-inspector.md) | TASK-002, TASK-003 | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Own checks pass; TASK-003 dependency remains blocked. |
| 5 | TASK-005 Native visual regression pass | D | BLOCKED | [watchtower/tasks/TASK-005-native-visual-regression.md](watchtower/tasks/TASK-005-native-visual-regression.md) | TASK-003, TASK-004 | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Current display caps native proof at 1299px. |

TASK Status labels: TODO, IN PROGRESS, BLOCKED, DONE.
Plan-level Status header: ACTIVE while any row is open, DONE when all rows DONE, ARCHIVED after archive.

## Plan Verify

- `swift package --package-path app/Atelier resolve` -> dependencies resolve without lowering SwiftUI-Introspect `26.0.1`.
- `swift build --package-path app/Atelier` -> build completes.
- `app/Atelier/.build/debug/Atelier --selftest` -> `SELFTEST: ALL PASS`.
- `rg -n "LuminareWindow|LuminarePane|luminareBackground" app/Atelier/Sources/Atelier` -> no production shell replacement.
- Computer Use at 1000px and 1600px widths -> Explorer, Terminal, and Git remain visible and usable.

## Handoff

- Implemented dependency, adapter, button, and status-card work.
- Build, self-test, package, signing, 1000px layout, and core Git action checks pass.
- Next action: verify 1600px on a larger display, plus reload, shortcut, hover, pressed, and focus states.

## Archive

- [20260716-atelier-mvp-milestones](watchtower/archive/20260716-atelier-mvp-milestones/)
