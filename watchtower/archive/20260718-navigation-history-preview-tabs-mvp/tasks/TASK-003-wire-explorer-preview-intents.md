# TASK-003 Wire Explorer Preview Intents

Group: B (native Explorer and editor integration)

## Brief

Goal: Make Explorer the only preview source. Keep Quick Open and every other file route permanent.

Change: Explorer selection opens permanent tabs -> single-click previews and double-click permanent opens.

How:

- Split the file tree callback into preview and permanent open intents.
- Map the native outline single action to preview for files.
- Map the native outline double action to permanent open for files.
- Keep directory expansion and creation targeting unchanged.
- Route Explorer preview into the new preview API from `WorkspaceView`.
- Keep Quick Open activation on `openFile(_:)` without adding a preview option.
- Keep created files, Gemma file links, and workspace service opens permanent.
- Add a native editor change callback that promotes the active preview before auto-save.
- Keep promotion idempotent so later edits have no tab lifecycle effect.
- Add deterministic routing and promotion tests where native events can call narrow model seams.

Files:

- [app/Atelier/Sources/Atelier/FileTree/FileTreeController.swift](app/Atelier/Sources/Atelier/FileTree/FileTreeController.swift) (single and double native file actions)
- [app/Atelier/Sources/Atelier/FileTree/FileTreeRepresentable.swift](app/Atelier/Sources/Atelier/FileTree/FileTreeRepresentable.swift) (preview and permanent callbacks)
- [app/Atelier/Sources/Atelier/FileTree/FileTreeView.swift](app/Atelier/Sources/Atelier/FileTree/FileTreeView.swift) (typed file open intents)
- [app/Atelier/Sources/Atelier/Workspace/Views/ContentView.swift](app/Atelier/Sources/Atelier/Workspace/Views/ContentView.swift) (Explorer preview wiring and permanent Quick Open path)
- [app/Atelier/Sources/Atelier/Editor/FileViewer.swift](app/Atelier/Sources/Atelier/Editor/FileViewer.swift) (native first-edit notification)
- [app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift](app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift) (pass edit promotion intent to the selected file view)
- [app/Atelier/Tests/AtelierTests/TerminalTabsNavigationTests.swift](app/Atelier/Tests/AtelierTests/TerminalTabsNavigationTests.swift) (permanent-route and edit-promotion tests)

Expected result:

- Explorer single-click replaces only the current preview.
- Explorer double-click keeps the file tab permanently.
- Typing once in a preview promotes it before another preview can replace it.
- Cmd+P always opens a permanent tab and records its recent-file entry.
- Created files and Gemma file links remain permanent.

Prompt:

```text
Wire Explorer preview and permanent open intents described in this TASK. Use NSOutlineView action and doubleAction, keep Quick Open on openFile(_:), and promote previews from the native editor change callback. Do not add preview behavior to any other route.
```

## Verify

- `swift test --package-path app/Atelier --filter TerminalTabsNavigationTests` -> route and promotion tests pass.
- Explorer single-click A, then B -> B replaces A as the only preview.
- Explorer double-click B -> B stays open after single-clicking C.
- Edit preview C, then single-click D -> C remains permanent and D becomes the preview.
- Cmd+P opens E, then single-click F -> E remains permanent and F is the preview.
