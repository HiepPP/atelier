# Learn 20260802-appearance-menu-bar-settings

## Summary

Discrepancy: 1 found. All 7 TASKs shipped as planned. A real bug outside the plan's scope
surfaced after implement: the menu bar panel opened off-screen on a Space with no Atelier window.
Found and fixed in the same session, driven by the user's manual click testing.

## Per TASK

- TASK-001: match. DESIGN.md got the Menu Bar section and the three text-scale rules as specced.
- TASK-002: match. Review fix pass corrected a real defect the spec did not foresee: the display
  key seed value leaked a phantom UserDefaults entry. Fixed inside the same TASK.
- TASK-003: match. Review flagged a missing launch verification and a stale DESIGN.md row list;
  both were routed out to the main session and closed after implement.
- TASK-004: match. Terminal and file tabs read their own scale as specced.
- TASK-005: match. Review fix restored a deleted test assertion the builder removed by mistake.
- TASK-006: match. Settings window Appearance section shipped as specced, review PASS with no fix.
- TASK-007: match. Review fix stopped a test from leaking a process-global flag into later tests.

## Plan-Level

- Scope gap, not a plan mistake: the plan never asked for cross-Space behavior, and no TASK's
  Verify checked it. `MenuBarExtra`'s `.window` style anchors its panel window to the Space that
  owned it at creation, so a click from another Space opened the panel out of sight. Runtime
  diagnostics (`RuntimeMenuBarSnapshot`, `MenuBarPanelObserver`) were added post-implement to
  make this observable, then one line (`collectionBehavior.insert(.moveToActiveSpace)`) fixed it
  in [app/Atelier/Sources/Atelier/Settings/AtelierMenuBarView.swift](../../app/Atelier/Sources/Atelier/Settings/AtelierMenuBarView.swift).
  User verification was in progress when this session ended.
- Order note: the plan's own manual-check list (TASK-003) asked to click the item once. It did
  not ask to click it from a different Space, which is exactly where the bug lived. A future menu
  bar or popover plan should add "click from a Space with no app window open" as a standing
  acceptance point.

## Lessons

- For any `MenuBarExtra` or menu-bar-adjacent feature, add a cross-Space manual check to the plan
  up front, not after a bug report. `.moveToActiveSpace` is one line; the bug it prevents reads to
  the user as "the icon disappeared."
- A KVO-based show/hide + click counter beat a polled snapshot for this class of bug. Sampling once
  a second missed the panel's transient state until counters replaced sampling; the counters gave
  a definitive answer on the first real trial.
