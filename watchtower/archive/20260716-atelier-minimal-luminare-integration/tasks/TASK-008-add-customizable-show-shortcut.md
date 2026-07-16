# TASK-008 Add customizable show shortcut

Group: G (keyboard access)

## Brief

Goal: Add one user-chosen global shortcut that raises Atelier from any application.

Change: no global shortcut -> native Settings recorder and persisted show shortcut

How:

- Keep KeyboardShortcuts imports inside one app-owned shortcut boundary.
- Add a named shortcut with no default key combination.
- Register one key-up handler that activates Atelier and raises its main window.
- Add a native `Settings` scene with a KeyboardShortcuts recorder wrapper.
- Preserve the existing Command-O Open Folder shortcut.
- Do not add shortcuts for Git mutations or terminal commands.

Files:

- [app/Atelier/Sources/Atelier/AtelierApp.swift](../../app/Atelier/Sources/Atelier/AtelierApp.swift) (Settings scene and shortcut lifecycle)
- [app/Atelier/Sources/Atelier/AtelierShortcuts.swift](../../app/Atelier/Sources/Atelier/AtelierShortcuts.swift) (single KeyboardShortcuts boundary)
- [app/Atelier/Sources/Atelier/AtelierSettingsView.swift](../../app/Atelier/Sources/Atelier/AtelierSettingsView.swift) (native Settings UI)
- [app/Atelier/Sources/Atelier/ContentView.swift](../../app/Atelier/Sources/Atelier/ContentView.swift) (inspect only; preserve Command-O)

Expected result:

- Users can record, change, and clear the show shortcut.
- The chosen shortcut persists across launches.
- The shortcut raises Atelier while another app is active.
- No accessibility or input-monitoring permission is requested.

## Verify

- `swift build --package-path app/Atelier` -> build completes.
- `app/Atelier/.build/debug/Atelier --selftest` -> `SELFTEST: ALL PASS`.
- `rg -l '^import KeyboardShortcuts' app/Atelier/Sources/Atelier` -> only `AtelierShortcuts.swift` is returned.
- Native Settings check -> record, change, clear, and relaunch persistence pass.
- Native cross-app check -> the chosen shortcut raises Atelier without a permission prompt.
- Native Command-O check -> Open Folder still works while Atelier is focused.
