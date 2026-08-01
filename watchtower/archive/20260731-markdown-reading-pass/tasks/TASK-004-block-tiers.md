# TASK-004 Apply the three block weight tiers

Group: A
Class: code

## Brief

Goal: Make a heavy block separate from prose more than a paragraph does. Today a table, a figure, a
callout, and a Mermaid figure all use the same gap as a plain paragraph, and a block quote uses half
of it.

Change: Replace the per-block gap choices with three named tiers on `MarkdownRhythm`.

How:

- Add three tier values to `MarkdownRhythm`: `flow` at `0.5u`, `structure` at `1.25u`, and `breakBefore`
  at `1.75u` with `breakAfter` at `0.6u`. Keep `u` as the snapped `bodyFont.lineHeight` it already is.
- Flow tier, `0.5u` before and after: paragraph, list item, lede.
- Structure tier, `1.25u` before and after: code card, table, image figure, Mermaid figure, callout,
  block quote, front matter card, footnotes section.
- Break tier, `1.75u` before and `0.6u` after: divider, H1, H2.
- H3 keeps `1u` before and `0.5u` after. It starts a section, it does not break one.
- Keep zero spacing between rows inside a table and between lines inside a code card. The tier
  applies to the block's outer edges only.
- Replace the existing `rhythm.paragraph`, `rhythm.paragraph * 0.5`, `rhythm.codeCard`, and
  `rhythm.divider` uses at the block append sites with the matching tier value.
- Keep `rhythm.lede` for the lede paragraph's trailing gap.
- Resolve every value during document build.

Files:

- [app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift](app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift):
  add the tier values to `MarkdownRhythm` and apply them at every block append site.
- [app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift](app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift):
  add a block spacing test.

Expected result:

- A block quote separates from the paragraph above it by `1.25u`, up from `0.25u`.
- A table, an image figure, a callout, and a Mermaid figure each separate by `1.25u`.
- A divider, an H1, and an H2 each open with `1.75u` and close with `0.6u`.
- Rows inside a table and lines inside a code card keep zero inter-row spacing.

## Verify

- `rg -n "rhythm.paragraph \* 0.5" app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift` -> no match, so the half-gap quote case is gone.
- `swift test --package-path app/Atelier --filter markdownBlockSpacingTiers` -> the new test passes.
  It builds a document holding a paragraph, a quote, a table, and a divider, then asserts each
  block's `paragraphSpacingBefore` against its tier.
- `swift test --package-path app/Atelier --filter nativeMarkdownFrontMatterCard` -> the existing
  front matter test still passes.
- `swift build --package-path app/Atelier` -> build succeeds with no new warnings.
- `swift test --package-path app/Atelier` -> all tests pass.
