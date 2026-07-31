# NEXT

## Current Active Plan

- Title: Unify Markdown rendering on the native attributed builder
- Slug: 20260731-unify-markdown-renderers
- Status: ACTIVE
- Updated: 2026-07-31
- Progress: 5/6 DONE. Group A shipped through a fan-out builder, reviewer, and fixer pass.

## Tracker

One row per TASK. Group A ships as one transaction because the TASKs share the same two source files.

| Order | TASK | Group | Status | Spec | Deps | Context | Notes |
|-------|------|-------|--------|------|------|---------|-------|
| 1 | TASK-001 Update the Markdown design contract | A | DONE | [watchtower/tasks/TASK-001-design-contract.md](watchtower/tasks/TASK-001-design-contract.md) | - | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Repo rule: DESIGN.md changes before code. |
| 2 | TASK-002 Add a transcript mode to the builder | A | DONE | [watchtower/tasks/TASK-002-builder-transcript-mode.md](watchtower/tasks/TASK-002-builder-transcript-mode.md) | TASK-001 | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | One presentation switch, no second code path. |
| 3 | TASK-003 Render the transcript with a self-sizing native view | A | DONE | [watchtower/tasks/TASK-003-transcript-native-view.md](watchtower/tasks/TASK-003-transcript-native-view.md) | TASK-002 | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Keep the `AgentMarkdownView(source:)` call shape. |
| 4 | TASK-004 Port the Mermaid source toggle and copy control | A | DONE | [watchtower/tasks/TASK-004-transcript-overlay-controls.md](watchtower/tasks/TASK-004-transcript-overlay-controls.md) | TASK-003 | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Pointer cursor comes from `AtelierGhostButtonStyle`, not a second explicit call. |
| 5 | TASK-005 Delete the SwiftUI block renderer | A | DONE | [watchtower/tasks/TASK-005-remove-swiftui-renderer.md](watchtower/tasks/TASK-005-remove-swiftui-renderer.md) | TASK-003, TASK-004 | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Also migrates the pixel test at line 2415. |
| 6 | TASK-006 Drive the on-screen and idle CPU acceptance pass | standalone | BLOCKED | [watchtower/tasks/TASK-006-runtime-acceptance.md](watchtower/tasks/TASK-006-runtime-acceptance.md) | TASK-005 | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Runtime half measured. On-screen half needs the `computer-use` plugin, which is not installed. |

TASK Status labels: TODO, IN PROGRESS, BLOCKED, DONE.
Plan-level Status header: ACTIVE while any row is open, DONE when all rows DONE, ARCHIVED after archive.

## Plan Verify

- `swift build --package-path app/Atelier` -> build succeeds with no new warnings.
- `swift test --package-path app/Atelier` -> all tests pass.
- `app/Atelier/.build/debug/Atelier --selftest` -> self-test passes.
- `rg -n "blockView|tableGrid|listRow" app/Atelier/Sources/Atelier/Agent/AgentMarkdownView.swift` -> no matches, so only one renderer remains.
- `app/Atelier/scripts/build_and_run.sh run` -> the app builds, signs, installs, and launches.

## Handoff

- TASK-001 to TASK-005 shipped in one fan-out group. Plan Verify passed in the main session: build complete, 432 tests in 41 suites passed, `SELFTEST: ALL PASS`, no `blockView|tableGrid|listRow` match, app launched at PID 6030.
- The reviewer returned ISSUE and a fixer pass ran. It fixed an off-by-one in `MarkdownRegionShift.shifted`, where a region starting exactly at the Mermaid insert point never moved, and it reserved trailing width so the source toggle stops drawing over the diagram.
- TASK-004 deviation: the two controls carry no explicit `.atelierPointerCursor()`. `AtelierGhostButtonStyle` already ends in it at [app/Atelier/Sources/Atelier/Theme/AtelierComponents.swift](app/Atelier/Sources/Atelier/Theme/AtelierComponents.swift) line 454, and the repo rule forbids double-applying it.
- TASK-006 is BLOCKED, not skipped. Its runtime half is measured and recorded: `workspace.active` true, settled `cpuPercent` 0.0100, and zero new crash reports. Its three on-screen points are NOT DRIVEN because no `computer-use` plugin is installed.
- Next action: decide how to close TASK-006. Install the `computer-use` plugin and rerun it, or drive the three points by hand and record the result in [watchtower/tasks/TASK-006-outcome.md](watchtower/tasks/TASK-006-outcome.md).

## Archive

- None.
