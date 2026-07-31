# TASK-004 Outcome

## Outcome

Status: DONE

Changed:

- Added `flow`, `structure`, `breakBefore`, `breakAfter`, and `listItem` to `MarkdownRhythm` in
  [app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift](app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift).
  `paragraph` now reads `flow`, `codeCard` reads `structure`, and the H1 and H2 gaps read the break
  tier. The `divider` value is gone: a divider needs different before and after values, so both call
  sites now name `breakBefore` and `breakAfter` directly.
- Moved to the structure tier: block quote, front-matter card, callout label and body, image figure
  and its caption, Mermaid figure, footnotes section, and the table's leading spacer.
- Added a trailing spacer paragraph at the end of `appendTable`. Table cells carry no trailing gap,
  so without it a table closed with the next block's flow gap.
- Added the `markdownBlockSpacingTiers` test in
  [app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift](app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift).

Deviations from the spec, both reconciled into [DESIGN.md](DESIGN.md):

- List items keep half the flow gap on each edge, `0.25u`, so two neighbouring items still sit
  `0.5u` apart. Giving each item a full `0.5u` edge would have doubled every list gap. The tier rule
  in [DESIGN.md](DESIGN.md) now states this.
- The table's closing spacer is a new element the spec did not name. [DESIGN.md](DESIGN.md) now
  states it.

Contract:

- The block quote gap went from `0.25u` to `1.25u`, a five times increase. That is the largest single
  change in this TASK.
- Rows inside a table and lines inside a code card keep zero inter-row spacing.
- H3 keeps `1u` before and `0.5u` after.
- All values resolve during document build.

Verified:

- `rg -n "rhythm.paragraph \* 0.5" app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift` -> no match.
- `swift test --package-path app/Atelier --filter markdownBlockSpacingTiers` -> passed in 0.023
  seconds. It asserts `1.25u` before a quote, `0.5u` before the following paragraph, and `1.75u`
  before a divider.
- `swift test --package-path app/Atelier --filter nativeMarkdownFrontMatterCard` -> passed in 0.018
  seconds.
- `swift build --package-path app/Atelier` -> build complete, no new warnings.
- `swift test --package-path app/Atelier` -> 435 tests in 41 suites passed in 9.507 seconds.
