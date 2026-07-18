# TASK-001 Outcome

## Outcome

Status: DONE

Changed:

- Added explicit preview and permanent file tab dispositions.
- Kept `openFile(_:)` permanent and added one narrow preview entry point.
- Replaced old previews through normal editor cleanup and preserved permanent tab identity.
- Recorded recent files only after permanent open or preview promotion.

Contract:

- At most one preview file tab exists.
- Permanent file tabs are never downgraded or duplicated by preview requests.
- Preview browsing does not update Quick Open recent files.

Verified:

- `swift test --package-path app/Atelier --filter TerminalTabsNavigationTests` -> 4 tests passed.
- `swift build --package-path app/Atelier` -> build completed successfully.
- `git diff --check` -> no whitespace errors.
