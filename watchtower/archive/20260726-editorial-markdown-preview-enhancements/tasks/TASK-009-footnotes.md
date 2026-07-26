# TASK-009 Footnotes

Group: standalone

## Brief

Goal: Render Markdown footnote references and definitions without leaking source syntax.

Change: Literal `[^id]` syntax -> superscript references and one trailing Notes section.

How:

- Update the footnote contract in [DESIGN.md](../../DESIGN.md) before code.
- Run GitNexus impact for `AgentMarkdownBlock`, `AgentMarkdownBlock.parse`, `ParsedMarkdownDocument`, and `MarkdownAttributedDocumentBuilder.build`.
- Collect one-line `[^id]: text` definitions during parsing.
- Remove definition lines from normal block flow.
- Assign stable reference numbers in first-reference order.
- Preserve unresolved references as literal text.
- Render resolved references as accent superscript numbers.
- Append one Notes block after the final content block.
- Render a hairline, small serif label, and numbered secondary rows.
- Keep Notes out of the document outline.
- Update transcript rendering for the new block shape.
- Add parser, numbering, unresolved-reference, inline-style, and outline tests.

Files:

- [DESIGN.md](../../DESIGN.md) (footnote syntax and Notes section contract)
- [app/Atelier/Sources/Atelier/Agent/AgentMarkdownView.swift](../../app/Atelier/Sources/Atelier/Agent/AgentMarkdownView.swift) (definition collection, block model, inline references, and transcript rendering)
- [app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift](../../app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift) (native superscripts and Notes section)
- [app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift](../../app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift) (parser, inline, notes, and outline coverage)

Expected result:

- Resolved references display as superscript accent numbers.
- Definition lines do not render as stray paragraphs.
- One Notes section appears after document content.
- Outline entries remain unchanged.
- Reference IDs and numbering remain stable across the cached build.

Prompt:

```text
Use $swiftui-expert-skill. Update DESIGN.md first, then collect [^id]: definitions during parse, remove them from block flow, number resolved refs in first-reference order, render accent superscripts, append one Notes section with a hairline, small serif label, and numbered secondary rows, preserve unresolved refs literally, keep outline unchanged, and use stable IDs.
```

## Verify

- `swift test --package-path app/Atelier --filter AgentResponsesTests.markdownFootnotes --quiet` -> parser, numbering, styling, and outline tests pass.
- Mixed resolved and unresolved fixture -> unresolved syntax remains literal.
- `git diff --check` -> no whitespace errors.
