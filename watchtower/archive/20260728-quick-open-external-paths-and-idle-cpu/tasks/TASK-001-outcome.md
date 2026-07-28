# TASK-001 Outcome

## Outcome

Status: DONE

## Changed

- `DESIGN.md`: added the external absolute-path rules to "Quick Open and Command Palette"
  (accept `/` and `~/`, expand and resolve, lead the results, skip missing/directory/in-root paths,
  resolve off the main actor). Updated before any code edit.
- `app/Atelier/Sources/Atelier/Commands/AtelierPaletteSearch.swift`: added the pure policy
  `externalFileURL(query:workspaceRoot:)`, the wrapper `externalFileMatch(query:workspaceRoot:)`,
  and the `externalPathScore` constant.
- `app/Atelier/Sources/Atelier/Commands/AtelierPaletteModel.swift`: added a defaulted
  `workspaceRoot: URL?` init parameter and prepended the external match inside the existing
  detached search task, deduplicating against ranked index matches.
- `app/Atelier/Sources/Atelier/Workspace/State/WorkspaceSession.swift`: passed `rootURL` into
  `AtelierPaletteModel`.
- `app/Atelier/Tests/AtelierTests/AtelierTests.swift`: added three tests covering the policy and
  the model wiring.
- `app/Atelier/Sources/Atelier/Commands/AtelierPaletteView.swift`: NOT changed. The existing
  `fileRow` already renders `candidate.relativePath` in the required monospaced secondary style
  with middle truncation. The external candidate carries its absolute path in that field, so the
  panel shows the file name first and the full absolute path second with no view edit. Adding a
  pass-through property would be single-use indirection, which the repository rules forbid.

## Contract

- Quick Open treats a query starting with `/` or `~/` as an absolute filesystem path. It expands
  `~`, standardizes the URL, and resolves symlinks.
- The resolved path becomes the first `fileResults` row, above ranked index matches, with score
  `AtelierPaletteSearch.externalPathScore` (50_000).
- The policy returns nil when the path is missing, is a directory, or resolves inside the
  workspace root. Indexed results stay the single source for in-workspace files.
- `WorkspaceFileIndex` is unchanged and still walks only the workspace root.
- Activation keeps the existing `AtelierPaletteSelection.file(URL)` route into
  `TerminalTabsModel.openFile(_:)`, so Markdown still opens in Preview mode.
- The filesystem existence check runs inside the existing `Task.detached` beside `rankFiles`, so
  typing never blocks the main actor.
- `AtelierPaletteModel.init` gained a defaulted `workspaceRoot` parameter; every existing call site
  compiles unchanged.

## Verified

- GitNexus impact before editing: `refreshFiles` upstream = CRITICAL (12 impacted, 5 processes);
  `AtelierPaletteModel` upstream = CRITICAL (177 impacted). Change is additive only, so no call
  site broke. Warning recorded.
- `swift build --package-path app/Atelier` -> `Build complete!`, clean.
- `swift test --package-path app/Atelier --filter quickOpenExternal` -> 3 tests, 3 passed.
- `swift test --package-path app/Atelier` -> 320 tests, 28 suites. Failures:
  `WorkspaceSearchTests.swift:653` and `PrecommitWhisperTests.swift:121-123`. A clean-tree control
  run (changes stashed) produced 317 tests with the identical failure set, so both are pre-existing
  timing flakes, not regressions. `WorkspaceToolExecutorTests.swift:90` passed in these runs and
  also flakes on a clean tree.
- Policy cases covered by unit tests: existing file outside the root returns its URL (with and
  without surrounding whitespace); a path inside the root returns nil; a missing path returns nil;
  a directory returns nil; a bare relative name and an empty query return nil; `~/` expands to the
  home directory; `~/` alone (a directory) returns nil; a `~/` path inside the root returns nil.
- Model-level test: an external path leads `fileResults` and drives `selection == .file(url)`; an
  in-root absolute path adds no absolute-path row; a missing path leaves results empty with
  `isSearching == false`.
- `app/Atelier/.build/debug/Atelier --selftest` -> `SELFTEST: ALL PASS`.
- `app/Atelier/scripts/build_and_run.sh run` -> SwiftLint gate passed, build complete, ad hoc
  signature valid, app launched. PID 10397 idle CPU 0.4% across two samples, inside the 0.2-2%
  band. No Atelier crash report in `~/Library/Logs/DiagnosticReports/`.
- `detect_changes` (unstaged) -> risk medium, 19 changed symbols across 5 files. Affected processes
  are only `PaletteOverlay` (2) and `ChooseWorkspace` (3, from the `WorkspaceSession.init`
  argument). No unexpected scope.
- Manual `Cmd-P` acceptance with
  `/private/tmp/claude-501/-Users-hiep-Projects-atelier/6f8d9bfb-e3e4-4f74-b747-275dfdedb67e/scratchpad/preview-check.md`
  was NOT run: the verification policy forbids Computer Use and screenshots here. The equivalent
  logic is proven by the model-level unit test, and that target file exists on disk.
