# TASK-002 Outcome

## Outcome

Status: DONE

## Changed

- `app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift`
- `app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift`

## Contract

`MarkdownAttributedDocumentBuilder.build` now takes
`presentation: AgentMarkdownPresentation = .document`. One switch, one code path.

- Body size: document `AtelierTypography.editorSize`, transcript `AtelierTypography.body`, both
  scaled by the environment scale and snapped to the display scale.
- Code size: document `AtelierTypography.uiSize`, transcript `AtelierTypography.label`. Without this
  branch transcript code would read larger than transcript prose.
- Transcript mode skips the three document-only treatments: the lede paragraph scale, the front
  matter masthead, and the H3 accent eyebrow color.
- Prose measure: document `documentMaxWidth`, transcript `transcriptMaxWidth`. It feeds figure
  reservation so a diagram cannot overflow the transcript measure.
- `MarkdownImageFigureLayout` and `MarkdownMermaidFigureLayout` helpers take an optional `measure`
  that defaults to `documentMaxWidth`, so the file Preview path is unchanged.
- `headingColor` takes the presentation. Every other block treatment stays shared.

## Blast radius (GitNexus impact, upstream)

`MarkdownAttributedDocumentBuilder.build`: risk LOW, 1 direct caller
(`Coordinator.update` in the same file), 1 process, 1 module. No HIGH/CRITICAL warning.

## Verified

- `swift build --package-path app/Atelier` -> build complete.
- `swift test --package-path app/Atelier` -> "Test run with 426 tests in 41 suites passed".
- New test "Transcript mode builds smaller body text than document mode" -> passed. Asserts
  transcript body 13.5 < document body 16 and that the default call still builds document mode.
- New test "Transcript mode skips the masthead and the lede scale" -> passed. Front matter plus H1
  in transcript mode keeps every key in the quiet card and emits no masthead row; the first
  paragraph stays at body size instead of the lede scale.
- New test "Transcript mode drops the H3 accent eyebrow color" -> passed.
- Every pre-existing builder test passed without edits.

## Review fixes

The review found that the 8,000-character transcript code cap was dropped when the SwiftUI renderer
went away. The old renderer applied `AgentCodeBlockPolicy.displayedContent` to the body and
`copiedContent` to the clipboard payload; `appendCode` applied neither.

- `appendCode` now takes `presentation`. Transcript mode renders
  `AgentCodeBlockPolicy.displayedContent(content)`; document mode still renders the whole file.
- `MarkdownCodeBlockRegion.source` stores `AgentCodeBlockPolicy.copiedContent(content)`, so the copy
  control still yields the full text.
- The highlight request now carries the displayed text, so highlight offsets match the rendered
  range.
- New test "A transcript code block renders capped while copy keeps it whole" -> passed. A body over
  the display limit renders truncated in transcript mode, its region source stays complete, and the
  document build keeps the full length.
- `swift build --package-path app/Atelier` -> build complete.
- `swift test --package-path app/Atelier` -> "Test run with 432 tests in 41 suites passed".
