# TASK-003 Migrate existing buttons

Group: B (button visuals)

## Brief

Goal: Apply the Luminare adapter to existing icon and primary buttons. Preserve all closures, roles, help text, shortcuts, and disabled rules.

Change: custom button drawing -> Luminare-backed Atelier adapters

How:

- Migrate Open Folder, folder selection, refresh, commit, reload, stage, unstage, discard, and new terminal controls.
- Keep terminal tab selection and change-row selection as native plain buttons.
- Keep [app/Atelier/Sources/Atelier/BranchControl.swift](../../app/Atelier/Sources/Atelier/BranchControl.swift) as a native `Menu`.
- Preserve 24px icon targets, 28px primary height, accent tint, and disabled opacity.
- Remove old button style types only after `rg` shows no references.

Files:

- [app/Atelier/Sources/Atelier/ContentView.swift](../../app/Atelier/Sources/Atelier/ContentView.swift) (folder buttons)
- [app/Atelier/Sources/Atelier/ChangesView.swift](../../app/Atelier/Sources/Atelier/ChangesView.swift) (Git action buttons)
- [app/Atelier/Sources/Atelier/TerminalTabs.swift](../../app/Atelier/Sources/Atelier/TerminalTabs.swift) (new terminal button)
- [app/Atelier/Sources/Atelier/AtelierLuminareStyle.swift](../../app/Atelier/Sources/Atelier/AtelierLuminareStyle.swift) (button adapters)
- [app/Atelier/Sources/Atelier/AtelierTheme.swift](../../app/Atelier/Sources/Atelier/AtelierTheme.swift) (remove unused styles only)

Expected result:

- Existing controls keep the same labels, actions, shortcuts, and enabled states.
- Hover and pressed states feel consistent without changing the warm VS Code palette.
- No button expands its column or toolbar unexpectedly.

## Verify

- `swift build --package-path app/Atelier` -> build completes.
- `app/Atelier/.build/debug/Atelier --selftest` -> `SELFTEST: ALL PASS`.
- `rg -n 'AtelierIconButtonStyle|AtelierPrimaryButtonStyle' app/Atelier/Sources/Atelier` -> no stale references after removal.
- Native GUI check -> every migrated button keeps its original action, help, shortcut, and disabled state.
