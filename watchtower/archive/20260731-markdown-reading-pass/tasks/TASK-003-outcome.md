# TASK-003 Outcome

## Outcome

Status: DONE

Changed:

- Split the heading size rule into `headingRatio(level:presentation:)` and rewrote `headingFont` in
  [app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift](app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift).
  All four `max()` clamps are gone. Sizes are pure ratios of body size.
- Document ratios are 1.85, 1.45, 1.18, 1.00, 0.92. Transcript ratios are 1.45, 1.28, 1.12, 1.00,
  0.92.
- Every heading level is now semibold. H4 and deeper were medium before.
- `headingColor` returns foreground for H4, so a body-size heading no longer reads quieter than the
  text under it. H5 and H6 stay secondary.
- H5 and H6 now take the same `0.6` kern H3 already used.
- Added the `markdownHeadingScale` test in
  [app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift](app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift).

Contract:

- The layout-pass H1 and H2 rule is unchanged, including the long and short accent lead segments and
  the `-0.5` kern.
- The document-only H3 accent eyebrow is unchanged.
- Heading sizes stay unsnapped, matching the previous behavior. Snapping them would break the exact
  ratio and was not part of this TASK.

Verified:

- `rg -n "max\(28|max\(22|max\(AtelierTypography" app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift` -> no match.
- `swift test --package-path app/Atelier --filter markdownHeadingScale` -> passed in 0.037 seconds.
  It asserts the five heading-to-body ratios are identical at text scale 0.8 and 1.6, that H1 is
  exactly 1.85 in document mode, and that H4 renders bold in foreground ink.
- `swift test --package-path app/Atelier --filter nativeMarkdownHeadingRule` -> passed in 0.088
  seconds.
- `swift build --package-path app/Atelier` -> build complete, no new warnings.
- `swift test --package-path app/Atelier` -> 434 tests in 41 suites passed in 8.740 seconds.
