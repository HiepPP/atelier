# TASK-004 Polish status and inspector surfaces

Group: C (status and Git inspector visuals)

## Brief

Goal: Use a small Luminare section wrapper for current Git status states. Keep the right column, split view, and all Git behavior unchanged.

Change: loose status layouts -> palette-controlled Atelier status sections

How:

- Add one `AtelierStatusCard` backed by `LuminareSection` through the adapter.
- Apply it to the Git error state and clean working-tree state.
- Keep the status bar as a flat 24px VS Code strip.
- Keep `ChangesView`, its `VSplitView`, branch row, commit row, and diff pane dimensions.
- Do not use `LuminarePane`, `LuminareWindow`, or translucent materials.
- Do not add a production Luminare popover. No current product action needs one.
- Keep the native branch `Menu` and discard `confirmationDialog` behavior.

Files:

- [app/Atelier/Sources/Atelier/AtelierLuminareStyle.swift](../../app/Atelier/Sources/Atelier/AtelierLuminareStyle.swift) (status section adapter)
- [app/Atelier/Sources/Atelier/ChangesView.swift](../../app/Atelier/Sources/Atelier/ChangesView.swift) (existing status states only)
- [app/Atelier/Sources/Atelier/ContentView.swift](../../app/Atelier/Sources/Atelier/ContentView.swift) (inspect only; keep shell and status bar unchanged)

Expected result:

- Clean and error states gain consistent spacing, border, and typography.
- Explorer, Terminal, and Git widths remain unchanged.
- Git refresh, stage, unstage, discard, commit, selection, and diff flows remain unchanged.
- No new popover, panel, state, or command ships.

## Verify

- `swift build --package-path app/Atelier` -> build completes.
- `app/Atelier/.build/debug/Atelier --selftest` -> `SELFTEST: ALL PASS`.
- `rg -n 'LuminareWindow|LuminarePane|luminareBackground|luminarePopover' app/Atelier/Sources/Atelier` -> no production usage.
- Native GUI check with clean and changed repositories -> status states change visually, while Git actions stay identical.
