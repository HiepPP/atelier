# TASK-001 Quick Open external paths

Group: A

## Brief

Goal: let `Cmd-P` Quick Open find and open a file that lives outside the current workspace root, by typing its absolute path.

Change: when the query looks like a filesystem path, offer that path as a direct result instead of relying on the workspace index.

How:

- Add a small pure policy that turns a query string into an optional external file URL.
  - Accept a query that starts with `/` or `~/`.
  - Expand `~` to the home directory.
  - Standardize the URL and resolve symlinks.
  - Return nil when the path does not exist or is a directory.
  - Return nil when the path is already inside the workspace root, so indexed results stay the single source for in-repo files.
- Call that policy from `refreshFiles()` in [app/Atelier/Sources/Atelier/Commands/AtelierPaletteModel.swift](../../app/Atelier/Sources/Atelier/Commands/AtelierPaletteModel.swift).
- Put the external match first in `fileResults`, above ranked index matches.
- Show the file name first and the full absolute path second, in the same monospaced style the panel already uses for relative paths.
- Keep the existing `AtelierPaletteSelection.file(URL)` activation path. `openFile(_:)` in [app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift](../../app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift) already takes any URL.
- Do the filesystem existence check off the main actor, inside the existing search task, so typing never blocks the UI.
- Do not widen `WorkspaceFileIndex` to walk outside the root. The index stays workspace scoped.
- Update [DESIGN.md](../../DESIGN.md) "Quick Open and Command Palette" before editing code.

Files:

- [DESIGN.md](../../DESIGN.md): add the external-path rule to the Quick Open section.
- [app/Atelier/Sources/Atelier/Commands/AtelierPaletteModel.swift](../../app/Atelier/Sources/Atelier/Commands/AtelierPaletteModel.swift): add the policy call and prepend the external match.
- [app/Atelier/Sources/Atelier/Commands/AtelierPaletteSearch.swift](../../app/Atelier/Sources/Atelier/Commands/AtelierPaletteSearch.swift): host the new pure path policy.
- [app/Atelier/Sources/Atelier/Commands/AtelierPaletteView.swift](../../app/Atelier/Sources/Atelier/Commands/AtelierPaletteView.swift): show an absolute path for an external match.
- [app/Atelier/Tests/AtelierTests/AtelierTests.swift](../../app/Atelier/Tests/AtelierTests/AtelierTests.swift): add tests for the path policy.

Expected result:

- Typing an absolute path to an existing file outside the repository shows one result at the top.
- Pressing Return opens that file in a permanent editor tab.
- The tab shows the file content, and Markdown files still open in Preview mode.
- Typing an absolute path inside the workspace root does not add a duplicate row.
- Typing a path that does not exist adds no row and shows no error.
- Normal fuzzy search over workspace files is unchanged.

Prompt:

```text
Add external absolute-path support to Quick Open. Update DESIGN.md first, then add a pure
path policy in AtelierPaletteSearch.swift, call it from AtelierPaletteModel.refreshFiles,
prepend the match, and render the absolute path in AtelierPaletteView. Add unit tests for
the policy. Do not widen WorkspaceFileIndex beyond the workspace root.
```

## Verify

- Run `swift build --package-path app/Atelier`. Expect a clean build.
- Run `swift test --package-path app/Atelier`. Expect the new path-policy tests to pass and no new failures.
- Run `app/Atelier/.build/debug/Atelier --selftest`. Expect `SELFTEST: ALL PASS`.
- Unit-test the policy with these cases:
  - An existing file outside the root returns its URL.
  - A path inside the workspace root returns nil.
  - A missing path returns nil.
  - A directory path returns nil.
  - A `~/` path expands to the home directory.
- Launch with `app/Atelier/scripts/build_and_run.sh run`, press `Cmd-P`, type the absolute path below, and confirm the file opens in a new tab:

```text
/private/tmp/claude-501/-Users-hiep-Projects-atelier/6f8d9bfb-e3e4-4f74-b747-275dfdedb67e/scratchpad/preview-check.md
```
