# TASK-002 Build the Deterministic Quick Open Core

Group: B (workspace file search and recent files)

## Brief

Goal: Build a bounded file index, session recent-file history, and deterministic fuzzy ranking. Keep filesystem work off MainActor and expose testable pure matching rules.

Change: File tree navigation only -> searchable workspace file candidates with session MRU ranking.

How:

- Add a workspace file index that returns relative file paths and absolute URLs.
- Reuse IgnoreRules and skip ignored directory subtrees.
- Do not follow directory symlinks outside or inside the workspace.
- Cache candidates for one fileTreeRevision and invalidate them on workspace changes.
- Add a pure case-insensitive subsequence scorer with explicit rank tiers.
- Use exact name, name prefix, path segment, consecutive match, MRU, and relative path tie-breaks.
- Cancel stale asynchronous searches and cap visible results at 100.
- Record up to 50 recent file URLs in TerminalTabsModel when openFile succeeds.
- Move reopened files to the front and remove missing or outside-workspace entries before display.
- Add deterministic tests for scoring, stable ties, ignored paths, cancellation state, MRU deduplication, and bounds.

Files:

- [app/Atelier/Sources/Atelier/Commands/AtelierPaletteSearch.swift](app/Atelier/Sources/Atelier/Commands/AtelierPaletteSearch.swift) (new pure candidate, scorer, and stable ranking types)
- [app/Atelier/Sources/Atelier/Commands/WorkspaceFileIndex.swift](app/Atelier/Sources/Atelier/Commands/WorkspaceFileIndex.swift) (new actor for bounded workspace enumeration)
- [app/Atelier/Sources/Atelier/Commands/AtelierPaletteModel.swift](app/Atelier/Sources/Atelier/Commands/AtelierPaletteModel.swift) (new MainActor query, cancellation, selection, and mode state)
- [app/Atelier/Sources/Atelier/FileTree/IgnoreRules.swift](app/Atelier/Sources/Atelier/FileTree/IgnoreRules.swift) (share subtree exclusion with the file index)
- [app/Atelier/Sources/Atelier/Workspace/State/WorkspaceSession.swift](app/Atelier/Sources/Atelier/Workspace/State/WorkspaceSession.swift) (own the workspace palette model and invalidate its file cache)
- [app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift](app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift) (record bounded session MRU files inside openFile)
- [app/Atelier/Tests/AtelierTests/AtelierPaletteSearchTests.swift](app/Atelier/Tests/AtelierTests/AtelierPaletteSearchTests.swift) (fuzzy ranking, file indexing, MRU, and cancellation tests)

Expected result:

- Empty file mode returns current-session recent files in MRU order.
- A non-empty query returns stable fuzzy matches from the active workspace.
- Equal inputs always produce the same result order across runs.
- Ignored directories and directory symlinks never produce candidates.
- Rapid query changes cannot replace newer results with stale results.

Prompt:

```text
Implement the Quick Open search core described in this TASK. Use an in-repo deterministic scorer and actor-isolated file enumeration. Keep result and MRU limits exact. Do not add a dependency, persistent history, text search, or symbol search.
```

## Verify

- `swift test --package-path app/Atelier --filter AtelierPaletteSearchTests` -> ranking, index, MRU, and cancellation tests pass.
- Build a temporary workspace with equal-score paths -> results use the documented relative-path tie-break.
- Build a temporary workspace with .git, .build, node_modules, DerivedData, and a directory symlink -> none appear in candidates.
- Open the same file three times -> one MRU entry remains at the front.
