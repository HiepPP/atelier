# TASK-005 Outcome

## Outcome

Status: DONE

Changed:

- Inline code in `inlineText` now uses `AppKitThemeAdapter.foreground` ink on an
  `AppKitThemeAdapter.raised` fill, in
  [app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift](app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift).
  The fill geometry, the single-fill rule, and the horizontal reservation are untouched. Only the
  two colors changed.
- List markers in `appendListItem` now fade from `AppKitThemeAdapter.secondary` toward the border
  color instead of from the accent. The three depth markers and the fade fraction are unchanged.
- The table header block fill in `appendTable` moved from the accent at `0.16` and `0.10` to
  `raised` at `0.55` in dark and `0.60` in light. The zebra rows stay at `raised` `0.26` and `0.30`,
  so the header is the same family several steps stronger. Semibold weight and the `0.4` kern are
  unchanged.
- `AgentMarkdownInlinePolicy.cachedAttributedString` in
  [app/Atelier/Sources/Atelier/Agent/AgentMarkdownView.swift](app/Atelier/Sources/Atelier/Agent/AgentMarkdownView.swift)
  now matches: primary ink on `AtelierTheme.raised`.
- Added the `markdownInlineCodeNeutralFill` test in
  [app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift](app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift).

Findings while working:

- The pure inline-code table cell needed no separate change. The `.atelierInlineCode` attribute
  already draws one continuous fill in the layout pass, so the cell chip follows the inline-code
  colors automatically.
- No mode branch was needed. Both presentations share the same inline-code path, which confirms
  there is still only one renderer.
- `AgentMarkdownInlinePolicy.pureCodeContent` now has no callers. It went dead when the SwiftUI
  block renderer was deleted in the previous plan. Left in place: deletion was not in this TASK.

Contract:

- Terracotta still marks the block-quote rule and its opening glyph, callout rules and glyphs, links
  and link underlines, footnote numbers, the document-mode H3 eyebrow, the H1 and H2 rule lead, the
  front-matter key column, and the caret. Nine display jobs became six.
- Selection color, caret color, and link activation are unchanged.

Verified:

- `swift test --package-path app/Atelier --filter markdownInlineCodeNeutralFill` -> passed in 0.024
  seconds. It asserts inline code carries foreground ink on the raised fill, and that no block
  background in the document equals the old accent header wash.
- `swift test --package-path app/Atelier --filter markdownTableBlocks` -> passed in 0.001 seconds.
- `swift build --package-path app/Atelier` -> build complete, no new warnings.
- `swift test --package-path app/Atelier` -> 436 tests in 41 suites passed in 9.068 seconds.
