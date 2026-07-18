# Plan Context

## Shared Context

- Atelier is a macOS 26 SwiftUI app built with Swift 6.2 and strict concurrency.
- [app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift](app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift) owns center tabs, selection, recent files, and tab chrome.
- [app/Atelier/Sources/Atelier/FileTree/FileTreeController.swift](app/Atelier/Sources/Atelier/FileTree/FileTreeController.swift) maps native outline actions to file open callbacks.
- [app/Atelier/Sources/Atelier/Editor/FileViewer.swift](app/Atelier/Sources/Atelier/Editor/FileViewer.swift) owns native editor change events and auto-save.
- [app/Atelier/Sources/Atelier/Commands/AtelierActionRegistry.swift](app/Atelier/Sources/Atelier/Commands/AtelierActionRegistry.swift) owns global action metadata, availability, and dispatch.
- [app/Atelier/Sources/Atelier/App/AppCommands.swift](app/Atelier/Sources/Atelier/App/AppCommands.swift) owns default menu shortcuts.

## Product Contract

- Navigation history is session-only and clears when the workspace closes.
- History stores file URLs and open disposition. It does not store cursor or scroll positions.
- Back and Forward cover file navigation only. Terminal, Git diff, and Gemma tabs stay outside history.
- A normal file navigation clears the Forward stack. Back and Forward do not record themselves.
- Each history stack keeps at most 100 entries and removes consecutive duplicate targets.
- Reopen Closed Tab restores permanent file tabs in last-closed-first order.
- Preview replacement and preview closure never enter closed history.
- Explorer single-click opens a preview. Explorer double-click opens or promotes a permanent tab.
- Only one preview file tab can exist. A new preview replaces the old preview.
- A permanent tab is never downgraded to preview.
- The first editor change promotes its preview before auto-save completes.
- Cmd+P, created files, Gemma file links, and existing non-Explorer routes stay permanent.
- Preview browsing does not update Quick Open recent files until the file becomes permanent.

## Native UI Contract

- Put small Back and Forward controls at the leading edge of the center tab bar.
- Keep both controls visible. Disable them when their history stacks are empty.
- Use Control-minus for Back and Control-Shift-minus for Forward.
- Use Command-Shift-T for Reopen Closed Tab.
- Keep Command-P bound to Quick Open and Command-Shift-P bound to the command palette.
- Mark preview tabs with subtle text styling and an accessibility value. Do not add another icon.
- Preserve horizontal tab scrolling, tab reordering, rename, word wrap, and agent response controls.

## Decisions

- This MVP has no pinned tabs, persistent history, cursor restoration, or custom keymap settings.
- Reopen Closed Tab restores permanent file tabs only.
- Missing files may reopen into the existing editor error state. This plan adds no recovery dialog.
- No package dependency is allowed.

## Open Decisions

- None.

## References

- [app/Atelier/Sources/Atelier/Workspace/Views/ContentView.swift](app/Atelier/Sources/Atelier/Workspace/Views/ContentView.swift)
- [app/Atelier/Sources/Atelier/FileTree/FileTreeRepresentable.swift](app/Atelier/Sources/Atelier/FileTree/FileTreeRepresentable.swift)
- [app/Atelier/Sources/Atelier/FileTree/FileTreeView.swift](app/Atelier/Sources/Atelier/FileTree/FileTreeView.swift)
- [app/Atelier/Tests/AtelierTests/AtelierActionRegistryTests.swift](app/Atelier/Tests/AtelierTests/AtelierActionRegistryTests.swift)
- `swift test --package-path app/Atelier`
