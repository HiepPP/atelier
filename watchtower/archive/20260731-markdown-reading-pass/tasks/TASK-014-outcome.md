# TASK-014 Outcome

## Outcome

Status: DONE

Changed:

- Replaced the fixed `keyColumnPercentage` constant with a bounded function in
  [app/Atelier/Sources/Atelier/Agent/AgentMarkdownView.swift](app/Atelier/Sources/Atelier/Agent/AgentMarkdownView.swift).
  It takes the widest key's measured width, the cell padding, and the mode measure, and clamps the
  result between 22 and 48 percent.
- `appendFrontMatter` now measures the widest key with the real key font once per card and takes a
  `measure` argument, in
  [app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift](app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift).
- Removed `keyColumnWidth`, which had no callers.
- Stated the rule in [DESIGN.md](DESIGN.md).
- Added `frontMatterKeyColumnWidth` in
  [app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift](app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift).

Second cause found only by looking, after the first fix still wrapped:

- The first version divided by the nominal measure, 720 points. The table resolves its percentages
  against the real text container, which here was about 690 points, because the window could not
  grant the full measure beside the outline rail and the sidecar. The computed share fit 720 and
  still wrapped at 690. Added `containerHeadroom` at `0.88` so the share is computed against a
  conservative container, and raised the ceiling from 42 to 48 percent to leave room for it.

Contract:

- The cell still wraps by character. That is the safety net for a key wider than the ceiling; it is
  no longer the normal path for a real key.
- Value column, nesting, masthead, and card layout are unchanged.

Verified:

- `swift test --package-path app/Atelier --filter frontMatterKeyColumnWidth` -> passed in 0.023
  seconds.
- `swift build --package-path app/Atelier` -> build complete, no new warnings.
- `swift test --package-path app/Atelier` -> 441 tests in 41 suites passed in 8.915 seconds.
- `app/Atelier/.build/debug/Atelier --selftest` -> `SELFTEST: ALL PASS`.
- `atelier-doctor status --json` -> `status healthy`, `workspace.active true`, settled `cpuPercent`
  0.0101, empty verdict list.
- `ls -t ~/Library/Logs/DiagnosticReports/ | grep -ci atelier` -> 0.

On-screen check, window 428935:

- `colors.surface.surface-hover`, `colors.surface.surface-active`, and
  `colors.surface.surface-selected` each sit on one line.
- Both 38-character keys, `colors.text.sidebar-primary-foreground` and
  `colors.text.sidebar-accent-foreground`, each sit on one line.
