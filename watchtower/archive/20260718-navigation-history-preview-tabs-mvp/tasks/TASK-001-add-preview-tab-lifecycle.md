# TASK-001 Add the Preview Tab Lifecycle

Group: A (file tab state foundation)

## Brief

Goal: Add explicit preview and permanent file tab states. Preserve every existing permanent file open route.

Change: Permanent file tabs only -> one replaceable preview plus permanent file tabs.

How:

- Add explicit preview and permanent file open dispositions to the center tab model.
- Keep `openFile(_:)` as the permanent API used by Quick Open and existing callers.
- Add a narrow preview API for later Explorer wiring.
- Replace the current preview when another file previews.
- Reuse an existing permanent tab instead of downgrading or duplicating it.
- Promote a preview when the same file opens permanently.
- Expose an idempotent promotion method for the editor change callback.
- Record recent files only after a permanent open or promotion.
- Close replaced previews through the normal resource cleanup path.
- Add deterministic tests for replacement, reuse, promotion, MRU rules, and cleanup.

Files:

- [app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift](app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift) (file open disposition, preview identity, promotion, and cleanup)
- [app/Atelier/Tests/AtelierTests/TerminalTabsNavigationTests.swift](app/Atelier/Tests/AtelierTests/TerminalTabsNavigationTests.swift) (new deterministic preview lifecycle tests)

Expected result:

- At most one preview file tab exists.
- Opening a permanent file never changes it into a preview.
- Opening the current preview permanently keeps its tab identity and promotes it.
- Preview browsing does not pollute Quick Open recent files.
- Terminal, Git diff, and Gemma tab behavior does not change.

Prompt:

```text
Implement the preview tab state described in this TASK. Keep openFile(_:) permanent for all existing callers. Add one narrow preview entry point, one preview at a time, idempotent promotion, and deterministic state tests. Do not wire Explorer or add navigation actions yet.
```

## Verify

- `swift test --package-path app/Atelier --filter TerminalTabsNavigationTests` -> preview replacement, permanent reuse, promotion, MRU, and cleanup tests pass.
- Open one permanent file, then request it as preview -> the existing permanent tab stays selected and permanent.
- Preview three files -> one preview tab remains and no preview URL enters recent files.
- `swift build --package-path app/Atelier` -> the tab model compiles under Swift 6.2 strict concurrency.
