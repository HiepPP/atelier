# TASK-005 Cut the accent budget from nine jobs to five

Group: A
Class: code

## Brief

Goal: Stop a technical answer from reading striped. Terracotta currently carries nine jobs, and the
two most frequent ones are inline code and list bullets.

Change: Move inline code, list bullets, and the table header to neutral surfaces. Leave every
semantic and interactive use of terracotta alone.

How:

- Inline code in `inlineText`: change the foreground from accent to `AppKitThemeAdapter.foreground`
  and the background from `AppKitThemeAdapter.accent.withAlphaComponent(0.12)` to
  `AppKitThemeAdapter.raised`. Do not change the fill geometry, the horizontal reservation, or the
  single-fill rule. Only the two colors change.
- Pure inline-code table cell in `appendTable`: the continuous chip adopts the same neutral fill.
  Keep it as one continuous shape so a soft-wrapped path does not zebra-stripe.
- List markers in `appendListItem`: change the depth fade to start from
  `AppKitThemeAdapter.secondary` instead of `AppKitThemeAdapter.accent`. Keep the same fade toward
  the border color and the same three depth markers.
- Table header in `appendTable`: replace the accent wash with a stronger `raised` fill. The header
  must stay clearly distinct from the zebra row fill, which uses `raised` at `0.26` in dark and
  `0.30` in light. Use `0.55` in dark and `0.60` in light for the header, then check on screen.
  Keep the header's semibold weight and light tracking.
- Do not change: the block quote accent rule and its opening glyph, the callout semantic colors,
  link ink and underline, footnote numbers, the document H3 accent eyebrow, the caret color, or the
  selection color.
- Add the same inline-code color change to the transcript mode. Both modes share one code path, so
  this should need no mode branch. If it does, that is a sign of a second code path; stop and report.

Files:

- [app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift](app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift):
  change colors in `inlineText`, `appendListItem`, and `appendTable`.
- [app/Atelier/Sources/Atelier/Agent/AgentMarkdownView.swift](app/Atelier/Sources/Atelier/Agent/AgentMarkdownView.swift):
  `AgentMarkdownInlinePolicy.cachedAttributedString` also paints inline code with accent ink on an
  accent fill. Match it to the new neutral treatment so the cached inline path agrees with the
  builder.
- [app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift](app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift):
  add an inline-code color test.

Expected result:

- Inline code renders as primary ink on a raised fill in both modes.
- List bullets render in secondary ink and still fade toward border by depth.
- The table header is clearly distinct from a zebra row without using terracotta.
- Block quotes, callouts, links, footnote numbers, and the document H3 eyebrow keep terracotta.

## Verify

- `rg -n "accent" app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift` -> the
  remaining matches are only the quote rule, callout colors, link colors, footnote numbers, the
  document H3 eyebrow, the caret, and the heading rule lead. No match sits inside `inlineText`,
  `appendListItem`, or the table header branch.
- `swift test --package-path app/Atelier --filter markdownInlineCodeNeutralFill` -> the new test
  passes. It asserts inline code carries foreground ink and a raised background.
- `swift test --package-path app/Atelier --filter markdownTableBlocks` -> the existing table test
  still passes.
- `swift build --package-path app/Atelier` -> build succeeds with no new warnings.
- `swift test --package-path app/Atelier` -> all tests pass.
