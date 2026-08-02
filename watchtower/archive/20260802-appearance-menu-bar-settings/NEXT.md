# Atelier NEXT

## Current Active Plan

Title: Menu bar appearance settings
Slug: 20260802-appearance-menu-bar-settings
Status: ARCHIVED
Updated: 2026-08-02

Add a macOS menu bar item for Atelier. The item opens a small panel that changes and remembers
appearance settings: terminal text size, app text size, editor text size, and zoom percent. The
panel also carries display sizing, focus mode, code ligatures, agent response text size, the
resource safety gate, and a reset action. The same controls appear in the Settings window.

## Tracker

| Order | TASK | Group | Status | Spec | Deps | Context | Notes |
|---|---|---|---|---|---|---|---|
| 1 | TASK-001 | docs | DONE | [watchtower/tasks/TASK-001-design-contract-appearance-settings.md](watchtower/tasks/TASK-001-design-contract-appearance-settings.md) | - | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Review skipped by the docs risk gate |
| 2 | TASK-002 | app-shell | DONE | [watchtower/tasks/TASK-002-appearance-scale-model.md](watchtower/tasks/TASK-002-appearance-scale-model.md) | TASK-001 | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Fix pass: first display key no longer writes a seed entry |
| 3 | TASK-003 | app-shell | DONE | [watchtower/tasks/TASK-003-menu-bar-extra-popover.md](watchtower/tasks/TASK-003-menu-bar-extra-popover.md) | TASK-002 | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Fix pass: launch check run, DESIGN.md row list routed out |
| 4 | TASK-004 | center-typography | DONE | [watchtower/tasks/TASK-004-terminal-editor-scale-wiring.md](watchtower/tasks/TASK-004-terminal-editor-scale-wiring.md) | TASK-002 | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Review PASS for this TASK |
| 5 | TASK-005 | center-typography | DONE | [watchtower/tasks/TASK-005-code-ligature-toggle.md](watchtower/tasks/TASK-005-code-ligature-toggle.md) | TASK-002 | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Fix pass: restored a deleted test assertion, seeded the revision |
| 6 | TASK-006 | settings-window | DONE | [watchtower/tasks/TASK-006-settings-window-appearance-section.md](watchtower/tasks/TASK-006-settings-window-appearance-section.md) | TASK-002 | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Review PASS, no fix needed |
| 7 | TASK-007 | tests | DONE | [watchtower/tasks/TASK-007-appearance-policy-tests.md](watchtower/tasks/TASK-007-appearance-policy-tests.md) | TASK-002 | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Fix pass: test no longer leaks the global ligature flag |

Waves for a team run:

- Wave 1: docs.
- Wave 2: app-shell.
- Wave 3: center-typography, settings-window, tests.

## Plan Verify

- `swift build --package-path app/Atelier` -> exit code 0.
- `swift test --package-path app/Atelier` -> every test passes.
- `app/Atelier/.build/debug/Atelier --selftest` -> self test passes.
- `app/Atelier/scripts/build_and_run.sh run` -> the app builds, signs, installs, and launches.
- `app/Atelier/scripts/atelier-doctor status --json` -> `status` is `healthy` and idle `cpuPercent`
  stays between 0.2 and 2 after 20 seconds of no interaction.
- `rg -n "atelier.appTextScale|atelier.terminalTextScale|atelier.editorTextScale" app/Atelier/Sources`
  -> every key is defined in one place, [app/Atelier/Sources/Atelier/Settings/AtelierAppearanceSettings.swift](app/Atelier/Sources/Atelier/Settings/AtelierAppearanceSettings.swift).

## Plan Verify Results

Run by the main session on 2026-08-02, after every group finished.

- `swift build --package-path app/Atelier` -> build complete, exit 0.
- `swift test --package-path app/Atelier --no-parallel` -> 484 tests in 47 suites passed.
- `swift test --package-path app/Atelier` (parallel) -> 2 suites fail on wall-clock deadlines:
  "Pre-commit whisper" and "File watcher delivery". Both pass alone
  (`--filter PrecommitWhisper` -> 9 tests passed, `--filter FileWatcherDelivery` -> 1 test passed)
  and both pass in the serial full run. Neither suite reads a typography, terminal, or zoom symbol.
  These are pre-existing load-sensitive flakes, not a regression from this plan.
- `app/Atelier/.build/debug/Atelier --selftest` -> SELFTEST: ALL PASS.
- `app/Atelier/scripts/build_and_run.sh run` -> built, ad hoc signed, `valid on disk`, installed and
  launched as PID 26234.
- `find ~/Library/Logs/DiagnosticReports -name 'Atelier*' -newermt '2026-08-02 19:10:00'` -> no match.
- `app/Atelier/scripts/atelier-doctor status --json` at 35 seconds uptime -> `status` healthy,
  `cpuPercent` 0.96, `heartbeatPaused` false, `heartbeatAgeMs` 512 against the 500 ms cadence,
  `verdicts` empty, `lastWriteError` null.
- `rg -n "atelier.appTextScale|atelier.terminalTextScale|atelier.editorTextScale" app/Atelier/Sources`
  -> the keys live only in
  [app/Atelier/Sources/Atelier/Settings/AtelierAppearanceSettings.swift](app/Atelier/Sources/Atelier/Settings/AtelierAppearanceSettings.swift).

## Open Manual Checks

No CLI path proves an on-screen result here, and the `computer-use` plugin is not installed. A
person must run these three:

1. Click the menu bar item. Press plus on Terminal text size three times. The terminal text grows and
   the sidebar text stays the same.
2. Open Settings, set App text size to 115%. The menu bar panel shows 115% on the App row.
3. In a terminal type `x != y --> z`, then turn off Code ligatures. The arrow and the not-equal glyph
   split into plain characters.

## Handoff

Next action: run the three manual checks above. After they pass, run `watchtower archive`, then
commit the change.

## Archive

- Archived: 2026-08-02 -> watchtower/archive/20260802-appearance-menu-bar-settings/
