# TASK-007 Outcome

## Outcome

Status: DONE

Scope correction found while reading the code:

- The TASK planned cross-card wiring to pick "the card owning the viewport top". The response panel
  renders exactly one card, `if let response = selectedResponse` in
  [app/Atelier/Sources/Atelier/Agent/AgentResponsesView.swift](app/Atelier/Sources/Atelier/Agent/AgentResponsesView.swift).
  There is no card stack, so no owning-card rule was needed and the highest risk in the plan did not
  exist. No new scroll observer was added.

Changed:

- Dropped `private` from `MarkdownStickySectionBar` in
  [app/Atelier/Sources/Atelier/Editor/FilePreview.swift](app/Atelier/Sources/Atelier/Editor/FilePreview.swift).
  It is shared, not copied. One definition remains in the source tree.
- Added `MarkdownTranscriptHeading` and an `onHeadingLayout` callback to `AgentMarkdownView` in
  [app/Atelier/Sources/Atelier/Agent/AgentMarkdownView.swift](app/Atelier/Sources/Atelier/Agent/AgentMarkdownView.swift).
  `MarkdownTranscriptCoordinator` keeps the heading ranges the builder already returns, reads each
  title and vertical offset after `ensureLayout` inside `height(forWidth:)`, and publishes the rows
  on the next runloop. It skips the publish when the rows are unchanged.
- Added `AgentResponseSectionBarPolicy`, a pure value type that maps the answer's top edge plus a
  heading offset to the active section title, and gates the bar at two headings.
- Wired the bar into the transcript in
  [app/Atelier/Sources/Atelier/Agent/AgentResponsesView.swift](app/Atelier/Sources/Atelier/Agent/AgentResponsesView.swift):
  a named coordinate space, an `onGeometryChange` read of the answer's top edge, a quantized
  `onScrollGeometryChange` read for reading progress, and a top overlay.
- Added the `transcriptSectionBarVisibility` test and fixed one existing test call that now needs
  the new `onHeadingLayout` argument, both in
  [app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift](app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift).
- Reconciled the two [DESIGN.md](DESIGN.md) rules to the shipped single-card design.

Design note:

- The active heading is derived from the answer's top edge in the scroll space plus each heading's
  offset inside the surface. That sum is the heading's distance from the viewport top, so no separate
  content-offset read is needed for the title.
- Reading progress is quantized to 1/200, so a passive scroll writes state only when the drawn pixel
  moves.

Contract:

- The bar carries `allowsHitTesting(false)` and `accessibilityHidden(true)` from the shared
  component. It never hit-tests, never animates during passive scroll, and never rebuilds the
  attributed document.
- Heading offsets are read after layout and published through `Task { @MainActor }`. The
  `onGeometryChange` action defers its state write the same way, so no layout-derived value mutates
  state inside AppKit's layout pass.
- The bar is an overlay, so it does not contribute to the measured column width.

Verified:

- `rg -n "private struct MarkdownStickySectionBar" app/Atelier/Sources/Atelier/Editor/FilePreview.swift` -> no match.
- `rg -c "struct MarkdownStickySectionBar" app/Atelier/Sources/Atelier/` -> exactly one definition.
- `swift test --package-path app/Atelier --filter transcriptSectionBarVisibility` -> passed in 0.001
  seconds. It asserts the bar stays off at one heading, holds the first title before the reader
  passes it, and switches to the second title after.
- `swift build --package-path app/Atelier` -> build complete, no new warnings.
- `swift test --package-path app/Atelier` -> 438 tests in 41 suites passed in 9.174 seconds.
- `app/Atelier/.build/debug/Atelier --selftest` -> `SELFTEST: ALL PASS`.
- `app/Atelier/scripts/build_and_run.sh run` -> built, signed ad hoc, installed, launched at PID
  74298.
- `atelier-doctor status --json` -> `status healthy`, `workspace.active true`, `cpuPercent` 0.0115
  then 0.0118 across two reads 30 seconds apart, `heartbeatPaused false`, `heartbeatAgeMs` 500,
  empty verdict list. Idle CPU sits below the 0.2 percent floor of the expected band, which is
  quieter than the bar, not a failure.
- `ls -t ~/Library/Logs/DiagnosticReports/ | grep -i atelier` -> no Atelier report.
- The bar's on-screen appearance is a visual claim. It is not proved here; TASK-008 owns it.
