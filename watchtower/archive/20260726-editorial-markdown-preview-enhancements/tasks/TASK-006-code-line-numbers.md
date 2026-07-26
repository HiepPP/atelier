# TASK-006 Code Line Numbers

Group: standalone

## Brief

Goal: Add a quiet line-number gutter to native fenced-code cards without changing copied code.

Change: Plain code body -> right-aligned secondary line-number gutter plus original code.

How:

- Update the code-card contract in [DESIGN.md](../../DESIGN.md) before code.
- Run GitNexus impact for `appendCode`, `MarkdownCodeBlockRegion`, and the native copy path.
- Add right-aligned line numbers and one explicit gutter tab stop.
- Use the code face at `0.85` scale and secondary color at `0.55` alpha.
- Keep source whitespace and wrapping unchanged.
- Mark line-number ranges so native selection copy can omit them.
- Keep `MarkdownCodeBlockRegion.source` unchanged for the code-card Copy button.
- Preserve syntax-highlight ranges against the original source characters.
- Allocate no line-number objects during draw.
- Add metadata, selection-copy, and syntax-range tests.

Files:

- [DESIGN.md](../../DESIGN.md) (line-number and copy contract)
- [app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift](../../app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift) (builder gutter, metadata, and native copy filtering)
- [app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift](../../app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift) (line-number and copy coverage)

Expected result:

- Every fenced-code line has a right-aligned gutter number.
- Card Copy and selected-text `Cmd-C` contain only original fenced source.
- Syntax colors remain attached to source text.
- Long lines still wrap without horizontal scrolling.

Prompt:

```text
Use $swiftui-expert-skill. Update DESIGN.md first, then add a right-aligned code line-number gutter with one tab stop, secondary 0.55 alpha, and codeFont at 0.85 scale. Exclude numbers from native selection copy, keep MarkdownCodeBlockRegion.source exact, preserve syntax ranges and wrapping, and allocate nothing during draw.
```

## Verify

- `swift test --package-path app/Atelier --filter AgentResponsesTests.markdownCodeLineNumbers --quiet` -> gutter, source range, and copy tests pass.
- Existing `markdownNativeCodeCardMetadata` test -> remains green.
- `git diff --check` -> no whitespace errors.
