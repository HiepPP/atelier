# NEXT

## Current Active Plan

- Title: Navigation History and Preview Tabs MVP
- Slug: 20260718-navigation-history-preview-tabs-mvp
- Status: ARCHIVED
- Updated: 2026-07-18

## Tracker

One row per TASK. Group ties together items that ship as one transaction.

| Order | TASK | Group | Status | Spec | Deps | Context | Notes |
|-------|------|-------|--------|------|------|---------|-------|
| 1 | TASK-001 Add the preview tab lifecycle | A | DONE | [watchtower/tasks/TASK-001-add-preview-tab-lifecycle.md](watchtower/tasks/TASK-001-add-preview-tab-lifecycle.md) | - | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Preview replacement, promotion, MRU, and cleanup verified. |
| 2 | TASK-002 Add session navigation history | A | DONE | [watchtower/tasks/TASK-002-add-session-navigation-history.md](watchtower/tasks/TASK-002-add-session-navigation-history.md) | TASK-001 | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Bounded history, branching, exclusions, and cleanup verified. |
| 3 | TASK-003 Wire Explorer preview intents | B | DONE | [watchtower/tasks/TASK-003-wire-explorer-preview-intents.md](watchtower/tasks/TASK-003-wire-explorer-preview-intents.md) | TASK-001, TASK-002 | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Native single-click, double-click, and edit-promotion flows verified. |
| 4 | TASK-004 Add navigation actions and native chrome | C | DONE | [watchtower/tasks/TASK-004-add-navigation-actions-and-native-chrome.md](watchtower/tasks/TASK-004-add-navigation-actions-and-native-chrome.md) | TASK-002, TASK-003 | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Registry actions, shortcuts, native chrome, accessibility, and exact-size checks verified. |

TASK Status labels: TODO, IN PROGRESS, BLOCKED, DONE.
Plan-level Status header: ACTIVE while any row is open, DONE when all rows DONE, ARCHIVED after archive.

## Plan Verify

- `swift test --package-path app/Atelier --filter TerminalTabsNavigationTests` passes all preview and history state tests.
- `swift test --package-path app/Atelier --filter AtelierActionRegistryTests` passes catalog, availability, and dispatch tests.
- `swift test --package-path app/Atelier --filter AtelierPalettePresentationTests` confirms new actions appear with live availability.
- `swift build --package-path app/Atelier` completes without errors.
- `swift test --package-path app/Atelier` passes the full deterministic suite.
- `app/Atelier/.build/debug/Atelier --selftest` passes all packaged checks.
- `git diff -- app/Atelier/Package.swift` returns no output because this MVP adds no package.
- Explorer single-click keeps at most one preview file tab and replaces the prior preview.
- Explorer double-click and the first editor change promote the selected preview to permanent.
- Cmd+P always opens or reuses a permanent file tab and never creates a preview.
- Back and Forward restore file navigation in session order without recording recursive entries.
- Reopen Closed Tab restores the newest closed permanent file and ignores preview replacement.
- At 760 x 512, navigation controls remain usable and the tab strip still scrolls horizontally.
- At 1440 x 900, preview styling, Back, Forward, and Reopen Closed Tab remain clear and keyboard accessible.
- Native checks record one narrow and one wide screenshot outside tracked paths.
- `app/Atelier/scripts/build_and_run.sh run` builds, signs, installs, and launches Atelier.

## Handoff

- Next action: Review the completed plan. No commit or push was performed.

## Archive

- Archived: 2026-07-18 -> watchtower/archive/20260718-navigation-history-preview-tabs-mvp/
