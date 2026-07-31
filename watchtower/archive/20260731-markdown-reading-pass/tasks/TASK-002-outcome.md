# TASK-002 Outcome

## Outcome

Status: DONE

Changed:

- Added `MarkdownTypeScale` in
  [app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift](app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift).
  It holds the seven ratios, a shared `lineHeight(of:)` helper, and one `lineSpacing(for:ratio:)`
  method that back-solves `pointSize * ratio - lineHeight` and snaps the result to device pixels.
- Replaced all twelve absolute `lineSpacing:` arguments in the builder with a ratio call that uses
  the font each block actually renders with. The nine remaining `lineSpacing: 0` sites are spacer
  and card-header paragraphs where zero is correct.
- Added a `rhythm` parameter to `appendMermaid` so the invalid-Mermaid source fallback can resolve
  its own code ratio.
- Hoisted three fonts above their paragraph style so the ratio call can read them: the block-quote
  serif italic font, the figure caption font, and the table cell font.
- Added the `markdownTypeScaleRatio` test in
  [app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift](app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift).

Deviation from the spec:

- The spec said to thread a separate scale value into every `append*` helper. Instead
  `MarkdownRhythm` stores it as `let type: MarkdownTypeScale`. Every helper already receives
  `rhythm`, so this adds no parameter to eleven call sites and keeps one owner for resolved rhythm.
  `MarkdownRhythm` now derives its `unit` from the same `MarkdownTypeScale.lineHeight(of:)` helper,
  so the two values cannot drift apart.

Contract:

- Line spacing is resolved during document construction only. Nothing is allocated in a draw,
  layout, or per-row path.
- `paragraphStyle(lineSpacing:before:after:...)` keeps its signature. Block gap values are untouched;
  TASK-004 owns those.
- Both presentation modes share one code path. No mode branch was added.

Verified:

- `rg -n "lineSpacing: AtelierMetrics" app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift` -> no match.
- `rg -n "struct MarkdownTypeScale" app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift` -> one match.
- `swift test --package-path app/Atelier --filter markdownTypeScaleRatio` -> passed in 0.042 seconds.
- `swift build --package-path app/Atelier` -> build complete, no new warnings.
- `swift test --package-path app/Atelier` -> 433 tests in 41 suites passed in 8.169 seconds.

Measured drift, the evidence the spec asked for:

- Old prose ratio, with the flat 8-point line spacing: 1.909 at transcript scale 0.8, 1.657 at
  transcript scale 1.3, 1.688 at document scale 1.0, and 1.438 at document scale 2.0. That is a
  0.47 spread across the range.
- New prose ratio: 1.62 at every one of those sizes, within 0.05, which the new test asserts.

Note:

- `swift test` trapped once in `WorkspaceVisibilityModel.update` at line 97, where `NSApp` is nil in
  the headless test host. This is the pre-existing flake already recorded in the previous plan's
  LEARN.md. It did not reproduce on the next run.
