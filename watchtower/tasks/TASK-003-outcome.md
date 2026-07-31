# TASK-003 Outcome

## Outcome

Status: DONE

## Changed

- `app/Atelier/Sources/Atelier/Agent/AgentMarkdownView.swift`
- `app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift`
- `app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift`

## Contract

`AgentMarkdownView(source:bodyFontSize:presentation:blocks:inlineRuns:)` keeps its call shape. Its
body now returns `MarkdownTranscriptTextView`, one bare `NSTextView` with no `NSScrollView`.

- `isEditable` false, `isSelectable` true, both resizable flags false, `textContainerInset` zero,
  `widthTracksTextView` true, `allowsNonContiguousLayout` false.
- `sizeThatFits` returns the used-rect height for the proposed width. The width falls back to the
  view bounds, then to the mode measure, so the surface cannot collapse.
- `MarkdownTranscriptCoordinator` caches the built document. It rebuilds only when the source,
  presentation, scale, display scale, or appearance changes.
- It reuses `MarkdownPreviewLayoutManager` and `MarkdownPreviewTextView`, so inline code chips,
  heading rules, quote bars, and link hover still draw.
- `bodyFontSize` became a scale factor over the mode base size, so
  `WorkspaceGemmaSearchView(bodyFontSize: editorSize)` still reads larger.
- Link clicks route through `NSTextViewDelegate` into the SwiftUI `openURL` action, so the workspace
  search view keeps its custom `atelier-source` scheme handler.
- The coordinator schedules syntax highlighting, local image decoding, and Mermaid rendering. A
  figure that changes height bumps a revision through `Task { @MainActor in }`, never inside the
  layout pass.
- `MarkdownImageFigureRenderer` became internal so the transcript coordinator can reuse it.

## Blast radius (GitNexus impact, upstream)

`AgentMarkdownView`: risk MEDIUM, 5 direct call sites (response panel, Gemma chat tab, Gemma
sidecar, Terminal Guardian card, workspace search), 13 impacted symbols, 2 modules. Not
HIGH/CRITICAL. All five call sites compile unchanged.

## Verified

- `swift build --package-path app/Atelier` -> build complete, no errors and no warnings.
- New test "The transcript surface sizes itself to its full content height" -> passed. A long source
  at width 320 reports a height above the single-line height and above ten body lines.
- `swift test --package-path app/Atelier` at this step -> 2 issues, both from the legacy
  `ImageRenderer` pixel test that TASK-005 migrates. Every other test passed. After TASK-005 the
  full suite passes: "Test run with 429 tests in 41 suites passed".
- `app/Atelier/scripts/build_and_run.sh run` -> built, ad-hoc signed, installed, launched. PID 77966
  stayed up; idle CPU 0.6% then 0.4%. No new Atelier crash report in
  `~/Library/Logs/DiagnosticReports/`.

## Not driven

- On-screen checks (selection crossing block types in one drag, a card growing to the full answer
  height with no inner scroll bar, the four other call sites rendering) were NOT driven. They need
  visual acceptance, which belongs to TASK-006 in the main session.

## Review fixes

The review found that figure reservation used the mode constant, not the host width. Two of the five
call sites (the Gemma sidecar and the Terminal Guardian card) are far narrower than 680 points, so a
figure overflowed instead of shrinking.

- `MarkdownTranscriptCoordinator.figureMeasure()` returns `min(mode measure, text container width)`
  and falls back to the mode measure while the container width is still unknown.
- `applyImage`, `applyMermaid`, and `applyMermaidFailure` read it at apply time instead of the
  measure captured when the load was scheduled. `scheduleMermaidRenders` derives its render width
  from it too.
- The coordinator now stores `imageFigures` as well, shifts them with the other regions, and
  resolves a figure's current range by id before invalidating layout. An image or diagram that
  finishes loading after a Mermaid toggle no longer invalidates a stale character range.
- `swift build --package-path app/Atelier` -> build complete.
- `swift test --package-path app/Atelier` -> "Test run with 432 tests in 41 suites passed".
- `app/Atelier/scripts/build_and_run.sh run` -> rebuilt, signed, installed, launched. PID 98842
  stayed up; idle CPU 0.9% then 0.1%. `atelier-doctor status --json` reported no write error and no
  dropped events.
- The narrow-host figure fit was NOT driven on screen. It needs visual acceptance in TASK-006.

## Note

`AgentResponsesView.selectableMarkdown` still branches on `textSelectionEnabled` to apply
`.textSelection(.enabled)`. That modifier is now a no-op over a representable, so the native surface
is always selectable. The flag was left alone because `AgentResponsesView.swift` is outside this
TASK's file list.
