# TASK-004 Terminal and editor scale wiring

Group: center-typography
Class: code

## Brief

Goal: Make the terminal read the terminal text scale and the file tabs read the editor text scale.
Everything else keeps the content scale.

Change: the center tab host passes `zoom.terminalScale` to terminal tabs and `zoom.editorScale` to
file tabs.

How:

- Edit [app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift](app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift):
  - In the `.terminal` case, change `TerminalView(controller:scale:isActive:)` to pass
    `zoom.terminalScale` instead of `zoom.contentScale`.
  - In the `.file` case, change `.environment(\.atelierZoomScale, zoom.contentScale)` to
    `zoom.editorScale`.
  - Leave the `.gitDiff` and `.gemma` cases on `zoom.contentScale`.
  - Leave the tab bar, the status bar, and the agent overlay on their current scales.
- Run `impact({target: "contentScale", direction: "upstream"})` first and check no other terminal or
  file surface depends on the old value.
- Do not change `TerminalController.updateScale`. It already snaps the size and skips a no-op.

Files:

- [app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift](app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift): terminal and file tab scale sources.

Expected result:

- Terminal text size follows the terminal scale only.
- File tab text size follows the editor scale only.
- Zoom still changes both, because zoom sits inside each derived value.

## Verify

- `swift build --package-path app/Atelier` -> exit code 0.
- `swift test --package-path app/Atelier` -> every test passes, including
  `TerminalTabsNavigationTests`.
- `rg -n "zoom.terminalScale|zoom.editorScale" app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift`
  -> one match each.
- `rg -n "scale: zoom.contentScale" app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift` -> no
  match, because the terminal no longer uses the content scale.
- `app/Atelier/scripts/atelier-doctor status --json` after 20 idle seconds -> `cpuPercent` stays
  between 0.2 and 2, so the new scale source added no redraw loop.
