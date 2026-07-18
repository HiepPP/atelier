# NEXT

## Current Active Plan

- Title: Quick Open and Action Registry MVP
- Slug: 20260718-quick-open-action-registry-mvp
- Status: ARCHIVED
- Updated: 2026-07-18

## Tracker

One row per TASK. Group ties together items that ship as one transaction.

| Order | TASK | Group | Status | Spec | Deps | Context | Notes |
|-------|------|-------|--------|------|------|---------|-------|
| 1 | TASK-001 Add the action registry foundation | A | DONE | [watchtower/tasks/TASK-001-add-action-registry-foundation.md](watchtower/tasks/TASK-001-add-action-registry-foundation.md) | - | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Typed catalog, live availability, dispatch, and menu routing verified. |
| 2 | TASK-002 Build the deterministic Quick Open core | B | DONE | [watchtower/tasks/TASK-002-build-deterministic-quick-open-core.md](watchtower/tasks/TASK-002-build-deterministic-quick-open-core.md) | TASK-001 | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Deterministic file index, fuzzy ranking, cancellation, and session MRU verified. |
| 3 | TASK-003 Integrate the native palette UI | C | DONE | [watchtower/tasks/TASK-003-integrate-native-palette-ui.md](watchtower/tasks/TASK-003-integrate-native-palette-ui.md) | TASK-001, TASK-002 | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Native file and command modes, keyboard flow, accessibility, and focus restore verified. |

TASK Status labels: TODO, IN PROGRESS, BLOCKED, DONE.
Plan-level Status header: ACTIVE while any row is open, DONE when all rows DONE, ARCHIVED after archive.

## Plan Verify

- `swift build --package-path app/Atelier` completes without errors.
- `swift test --package-path app/Atelier` passes all deterministic tests.
- `app/Atelier/.build/debug/Atelier --selftest` passes all packaged checks.
- `git diff -- app/Atelier/Package.swift` returns no output because the MVP adds no package.
- Cmd+P opens Quick Open only when a workspace exists.
- Cmd+Shift+P opens the command palette with or without an active workspace.
- Empty Quick Open shows session MRU files. A query shows stable fuzzy-ranked file results.
- Arrow keys, Return, and Escape work without a mouse in both palette modes.
- Closing either palette restores the prior terminal or editor responder when possible.
- The palette passes native checks at 760 x 512 and 1440 x 900 window sizes.
- `app/Atelier/scripts/build_and_run.sh run` builds, signs, installs, and launches Atelier.

## Handoff

- Next action: Review the completed diff. Archive this plan before a later commit.

## Archive

- Archived: 2026-07-18 -> watchtower/archive/20260718-quick-open-action-registry-mvp/
