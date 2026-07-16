# TASK-008 Outcome

## Outcome

Status: BLOCKED

Changed:
- Added the empty-by-default global shortcut name, handler, and recorder wrapper in [AtelierShortcuts.swift](../../app/Atelier/Sources/Atelier/AtelierShortcuts.swift).
- Added the native Settings form in [AtelierSettingsView.swift](../../app/Atelier/Sources/Atelier/AtelierSettingsView.swift).
- Registered the Settings scene and shortcut handler in [AtelierApp.swift](../../app/Atelier/Sources/Atelier/AtelierApp.swift).
- Added a lightweight marker that tracks only the workspace window.

Contract:
- No default shortcut is assigned.
- The handler activates Atelier and raises only the tracked workspace window.
- The Settings window is never selected by the show shortcut handler.
- KeyboardShortcuts stays behind [AtelierShortcuts.swift](../../app/Atelier/Sources/Atelier/AtelierShortcuts.swift).

Verified:
- `swift build --package-path app/Atelier` -> passed.
- `app/Atelier/.build/debug/Atelier --selftest` -> `SELFTEST: ALL PASS`.
- `rg -l '^import KeyboardShortcuts' app/Atelier/Sources/Atelier` -> only [AtelierShortcuts.swift](../../app/Atelier/Sources/Atelier/AtelierShortcuts.swift).
- Computer Use -> `Command-,` opened the native Atelier Settings window.
- Computer Use -> `Show Atelier:` recorder displayed the empty `Record Shortcut` placeholder.
- [build_and_run.sh](../../app/Atelier/script/build_and_run.sh) packaged the KeyboardShortcuts resource bundle.

Blocked:
- Cross-app activation was not tested because assigning a real global shortcut would choose a user preference.
- Record, change, clear, relaunch persistence, and Command-O still need the full native matrix.
