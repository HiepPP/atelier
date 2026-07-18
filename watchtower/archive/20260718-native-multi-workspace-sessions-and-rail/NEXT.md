# NEXT

## Current Active Plan

- Title: Native multi-workspace sessions and rail
- Slug: 20260718-native-multi-workspace-sessions-and-rail
- Status: ARCHIVED
- Updated: 2026-07-19

## Tracker

One group ships the state model, native workspace rail, and full verification together.

| Order | TASK | Group | Status | Spec | Deps | Context | Notes |
|-------|------|-------|--------|------|------|---------|-------|
| 1 | TASK-001 Define the multi-workspace contract | A | DONE | [watchtower/tasks/TASK-001-define-multi-workspace-contract.md](watchtower/tasks/TASK-001-define-multi-workspace-contract.md) | - | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Design and product contracts now define the shipped feature. |
| 2 | TASK-002 Build concurrent workspace sessions | A | DONE | [watchtower/tasks/TASK-002-build-concurrent-workspace-sessions.md](watchtower/tasks/TASK-002-build-concurrent-workspace-sessions.md) | TASK-001 | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Catalog, migration, lifecycle, persistence ordering, and cleanup pass verification. |
| 3 | TASK-003 Add the native workspace rail | A | DONE | [watchtower/tasks/TASK-003-add-native-workspace-rail.md](watchtower/tasks/TASK-003-add-native-workspace-rail.md) | TASK-002 | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Rail, recovery states, focus ownership, and action routing pass verification. |

TASK Status labels: TODO, IN PROGRESS, BLOCKED, DONE.

## Plan Verify

- `swift build --package-path app/Atelier` -> the package builds with Swift 6.2 strict concurrency.
- `swift test --package-path app/Atelier` -> all existing and multi-workspace tests pass.
- `app/Atelier/.build/debug/Atelier --selftest` -> persistence, loading, Git, and workspace checks pass.
- `app/Atelier/scripts/build_and_run.sh run` -> the updated app builds, installs, and opens.
- At `760 x 512`, the rail and center tab navigation remain usable without overlap.
- At `1440 x 900`, the rail, sidebar, center, and inspector keep clear visual hierarchy.
- Two live workspaces keep separate tabs, terminals, navigation, Git state, and agent state.
- Rapid switching does not stop terminals, reset tabs, leak focus, or create duplicate sessions.
- A missing saved folder stays visible as unavailable without blocking other workspaces.
- Light, dark, Reduce Motion, Reduce Transparency, keyboard, and VoiceOver labels remain correct.
- Store narrow and wide screenshots outside tracked paths.

## Handoff

- Next action: Archive this completed plan when the changes are ready to commit.

## Archive

- Archived: 2026-07-19 -> watchtower/archive/20260718-native-multi-workspace-sessions-and-rail/
