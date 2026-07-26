# TASK-004 Baseline Rhythm

Group: standalone

## Brief

Goal: Lock native Markdown block spacing to one font-derived rhythm.

Change: Mixed spacing tokens -> fixed multiples of one display-scale-snapped line-height unit.

How:

- Update the vertical-rhythm contract in [DESIGN.md](../../DESIGN.md) before code.
- Run GitNexus impact for `MarkdownAttributedDocumentBuilder.build`, `headingTopSpacing`, `appendCode`, and `appendTable`.
- Add `MarkdownRhythm` with a unit from `bodyFont.lineHeight`, snapped to `displayScale`.
- Set paragraph spacing to `0.5u`.
- Set H3 spacing to `1u` before and `0.5u` after.
- Set H1 and H2 spacing to `2u` before and `0.75u` after.
- Set divider spacing to `1.5u`, code-card spacing to `1u`, and lede spacing to `0.75u`.
- Remove the current ad hoc spacing sums from the native builder.
- Keep all values resolved during attributed-document construction.
- Add paragraph-style tests for each block class.

Files:

- [DESIGN.md](../../DESIGN.md) (baseline rhythm contract)
- [app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift](../../app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift) (rhythm policy and native builder spacing)
- [app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift](../../app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift) (spacing and display-scale coverage)

Expected result:

- Section spacing follows one stable vertical unit.
- Zoom and display scale produce snapped deterministic values.
- Scroll and draw paths perform no rhythm calculation.
- Existing text selection and document caching remain unchanged.

Prompt:

```text
Use $swiftui-expert-skill. Update DESIGN.md first, then add MarkdownRhythm from bodyFont.lineHeight snapped to displayScale. Use paragraph 0.5u, H3 1u before and 0.5u after, H1-H2 2u before and 0.75u after, divider 1.5u, code card 1u, and lede 0.75u. Remove ad hoc spacing sums and keep one source of vertical spacing.
```

## Verify

- `swift test --package-path app/Atelier --filter AgentResponsesTests.nativeMarkdownRhythm --quiet` -> all rhythm tests pass.
- Existing code-block spacing tests -> remain green.
- `git diff --check` -> no whitespace errors.
