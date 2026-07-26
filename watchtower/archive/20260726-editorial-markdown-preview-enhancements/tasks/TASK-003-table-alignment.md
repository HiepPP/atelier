# TASK-003 Table Alignment

Group: standalone

## Brief

Goal: Honor Markdown table alignment and make numeric columns scan cleanly.

Change: Dropped delimiter alignment -> per-column alignment with tabular numeric figures.

How:

- Update the table contract in [DESIGN.md](../../DESIGN.md) before code.
- Run GitNexus impact for `AgentMarkdownBlock`, `AgentMarkdownBlock.parse`, and `appendTable`.
- Add `MarkdownColumnAlignment` and store one value per table column.
- Parse delimiter cells such as `:--`, `:-:`, and `--:` before discarding the row.
- Apply left, center, or right paragraph alignment to every native cell.
- Detect numeric-majority columns from non-empty data cells during document construction.
- Force numeric-majority columns right and use `bodyFont.monospacedDigit`.
- Apply matching alignment to the transcript table renderer.
- Keep existing bounded column weights and wrapping rules.
- Add parser, alignment, numeric-majority, and mixed-table tests.

Files:

- [DESIGN.md](../../DESIGN.md) (table alignment and numeric rules)
- [app/Atelier/Sources/Atelier/Agent/AgentMarkdownView.swift](../../app/Atelier/Sources/Atelier/Agent/AgentMarkdownView.swift) (alignment model, parser, and transcript table)
- [app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift](../../app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift) (native cell alignment and figures)
- [app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift](../../app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift) (delimiter and rendering coverage)

Expected result:

- Delimiter syntax controls each column's alignment.
- Numeric-majority columns use aligned tabular figures.
- Column widths remain bounded and deterministic.
- Wide and wrapped tables keep one selectable native surface.

Prompt:

```text
Use $swiftui-expert-skill. Update DESIGN.md first, then implement table alignment. Parse |:--|:-:|--:| into MarkdownColumnAlignment values, align each cell, use monospacedDigit and trailing alignment for numeric-majority columns, preserve bounded deterministic column weights, and do no recalculation during scroll or draw.
```

## Verify

- `swift test --package-path app/Atelier --filter AgentResponsesTests.markdownTableAlignment --quiet` -> delimiter and rendering tests pass.
- Existing wrapped-table tests -> remain green.
- `git diff --check` -> no whitespace errors.
