# TASK-003 Integrate the Native Palette UI

Group: C (Quick Open and command palette vertical slice)

## Brief

Goal: Ship one native keyboard-first palette surface for files and commands. Keep active terminal and editor views mounted and restore their responder after dismissal.

Change: No palette -> Cmd+P Quick Open and Cmd+Shift+P command palette.

How:

- Add one SwiftUI palette view with file and command presentation modes.
- Use native TextField, List, Button, selection, and accessibility APIs.
- Present the palette above ContentView without replacing workspace content.
- Capture the current AppKit first responder before presentation.
- Focus the query field after presentation and restore the prior responder on close.
- Bind Cmd+P to file mode and disable it without an active workspace.
- Bind Cmd+Shift+P to command mode and keep Open Folder available without a workspace.
- Support Arrow Up, Arrow Down, Return, and Escape without a mouse.
- Open selected files through TerminalTabsModel.openFile.
- Execute selected commands through AtelierActionRegistry using current state.
- Show command category, shortcut, file name, and relative path without extra icon noise.
- Preserve selection when asynchronous file results update if the same item remains.
- Add deterministic presentation-state tests for mode, selection, dismissal, and disabled commands.

Files:

- [app/Atelier/Sources/Atelier/Commands/AtelierPaletteView.swift](app/Atelier/Sources/Atelier/Commands/AtelierPaletteView.swift) (new native palette surface and rows)
- [app/Atelier/Sources/Atelier/Commands/AtelierPaletteModel.swift](app/Atelier/Sources/Atelier/Commands/AtelierPaletteModel.swift) (presentation mode, selection, activation, and dismissal state)
- [app/Atelier/Sources/Atelier/App/AppCommands.swift](app/Atelier/Sources/Atelier/App/AppCommands.swift) (Cmd+P and Cmd+Shift+P focused scene commands)
- [app/Atelier/Sources/Atelier/Workspace/Views/ContentView.swift](app/Atelier/Sources/Atelier/Workspace/Views/ContentView.swift) (palette presentation, workspace binding, and responder handoff)
- [app/Atelier/Sources/Atelier/Platform/WindowController.swift](app/Atelier/Sources/Atelier/Platform/WindowController.swift) (reuse or narrowly extend native responder helpers)
- [app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift](app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift) (open selected file and expose current tab action state)
- [app/Atelier/Tests/AtelierTests/AtelierPalettePresentationTests.swift](app/Atelier/Tests/AtelierTests/AtelierPalettePresentationTests.swift) (mode, selection, availability, and dismissal tests)

Expected result:

- Cmd+P opens focused Quick Open in an active workspace.
- Cmd+Shift+P opens focused command search from empty and workspace states.
- File selection opens or reuses the existing file tab.
- Command selection runs the registry action with current availability.
- Escape closes the palette and returns focus when possible.
- The overlay stays usable at narrow and wide window sizes.

Prompt:

```text
Implement the native palette vertical slice described in this TASK. Use one SwiftUI surface for file and command modes. Reuse WindowController for AppKit responder capture and restore. Keep terminal and editor views mounted. Do not add NSPanel, preview, multi-select, custom keymaps, or new dependencies.
```

## Verify

- `swift test --package-path app/Atelier --filter AtelierPalettePresentationTests` -> presentation and selection tests pass.
- At 760 x 512, Cmd+P opens, filters, selects, opens a file, and restores editor focus after Escape.
- At 1440 x 900, Cmd+Shift+P filters commands and runs one enabled command with Return.
- With no workspace, Cmd+P is disabled and Cmd+Shift+P still exposes Open Folder.
- With a terminal focused, open and close both palette modes -> terminal input continues in the same process.
- VoiceOver labels identify the query, selected row, command shortcut, and file relative path.
- `app/Atelier/scripts/build_and_run.sh run` -> Atelier builds, signs, installs, and launches.
