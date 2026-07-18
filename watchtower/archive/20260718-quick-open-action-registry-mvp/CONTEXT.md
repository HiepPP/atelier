# Plan Context

## Shared Context

- Atelier is a macOS 26 SwiftUI app built with Swift 6.2 and strict concurrency.
- [app/Atelier/Sources/Atelier/App/AppCommands.swift](app/Atelier/Sources/Atelier/App/AppCommands.swift) defines global menu actions and default shortcuts.
- [app/Atelier/Sources/Atelier/App/AppModel.swift](app/Atelier/Sources/Atelier/App/AppModel.swift) owns application actions and the active workspace.
- [app/Atelier/Sources/Atelier/Workspace/State/WorkspaceSession.swift](app/Atelier/Sources/Atelier/Workspace/State/WorkspaceSession.swift) owns workspace services and feature models.
- [app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift](app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift) opens files and owns selected center tabs.
- [app/Atelier/Sources/Atelier/FileTree/IgnoreRules.swift](app/Atelier/Sources/Atelier/FileTree/IgnoreRules.swift) defines paths excluded from workspace browsing.
- [app/Atelier/Sources/Atelier/Platform/WindowController.swift](app/Atelier/Sources/Atelier/Platform/WindowController.swift) captures and restores the native first responder.

## Product Contract

- Cmd+P opens Quick Open for the active workspace.
- Cmd+Shift+P opens the command palette.
- Quick Open searches file names and relative paths only.
- An empty Quick Open query shows recent files from the current workspace session.
- Opening a recent file moves it to the front and removes duplicate entries.
- Command availability follows current application and workspace state.
- A selected file opens through the existing center-tab path.
- A selected command runs through one typed action dispatcher.

## Search Contract

- Use a small in-repo fuzzy scorer. Do not add a package dependency.
- Match case-insensitive subsequences in file names and relative paths.
- Rank exact file names before prefixes, segment matches, and loose subsequences.
- Use recent-file order as a stable boost, then relative path as the final tie-break.
- Keep at most 100 visible results and 50 recent file URLs.
- Cancel stale searches when the query or workspace file revision changes.
- Exclude ignored directories, hidden build output, and followed directory symlinks.

## Native UI Contract

- Use one SwiftUI palette surface for file and command modes.
- Use native TextField, List, Button, keyboard commands, and accessibility labels.
- Use the existing AppKit responder bridge for focus capture and restore.
- Do not add a custom NSPanel, web view, or browser-style overlay.
- Keep the current terminal and editor views mounted while the palette is visible.
- Support Arrow Up, Arrow Down, Return, and Escape without a mouse.

## Decisions

- Recent files stay in memory for this MVP. They do not change workspace persistence.
- The command palette uses stable registry order. It does not persist command usage.
- Existing focus-local rename and word-wrap commands stay on FocusedValues.
- Quick Open does not create files from unmatched queries.
- The MVP has no text search, symbol search, preview pane, multi-select, or custom keymap editor.
- No new package dependency is allowed.

## Open Decisions

- None.

## References

- [app/Atelier/Sources/Atelier/App/AtelierApp.swift](app/Atelier/Sources/Atelier/App/AtelierApp.swift)
- [app/Atelier/Sources/Atelier/Workspace/Views/ContentView.swift](app/Atelier/Sources/Atelier/Workspace/Views/ContentView.swift)
- [app/Atelier/Tests/AtelierTests/AtelierTests.swift](app/Atelier/Tests/AtelierTests/AtelierTests.swift)
- `swift test --package-path app/Atelier`
