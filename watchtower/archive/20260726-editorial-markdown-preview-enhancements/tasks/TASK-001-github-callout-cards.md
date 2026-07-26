# TASK-001 GitHub Callout Cards

Group: standalone

## Brief

Goal: Render GitHub callouts as quiet tinted cards. Keep ordinary block quotes unchanged.

Change: Literal `> [!NOTE]` pull-quotes -> semantic callout cards for five GitHub kinds.

How:

- Update the Markdown preview contract in [DESIGN.md](../../DESIGN.md) before code.
- Run GitNexus impact for `AgentMarkdownBlock`, `AgentMarkdownBlock.parse`, and `MarkdownAttributedDocumentBuilder.build`.
- Add `MarkdownCalloutKind` and a callout block case.
- Detect `NOTE`, `TIP`, `IMPORTANT`, `WARNING`, and `CAUTION` before normal quote parsing.
- Remove the marker line and merge the following quoted lines into the callout body.
- Render one native `NSTextTableBlock` card with an accent-family left rule.
- Use a glyph and accent micro label. Keep body text at full contrast and non-italic.
- Map all five kinds to existing semantic tokens. Add no hue.
- Update the transcript renderer for the new exhaustive block case.
- Add parser and native attributed-document tests for all five kinds.

Files:

- [DESIGN.md](../../DESIGN.md) (callout contract and token rules)
- [app/Atelier/Sources/Atelier/Agent/AgentMarkdownView.swift](../../app/Atelier/Sources/Atelier/Agent/AgentMarkdownView.swift) (block model, parser, and transcript rendering)
- [app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift](../../app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift) (native callout card)
- [app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift](../../app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift) (parser and builder coverage)

Expected result:

- All five GitHub callout forms render without literal marker text.
- Callout bodies remain selectable inside the single native document.
- Ordinary `>` blocks retain the editorial pull-quote style.
- Transcript and file-preview switches remain exhaustive and consistent.

Prompt:

```text
Use $swiftui-expert-skill. Update DESIGN.md first, then implement GitHub callout cards. Support > [!NOTE|TIP|IMPORTANT|WARNING|CAUTION], one NSTextTableBlock card, an accent left rule, a glyph plus accent micro label, full-contrast body text, existing tokens only, no new hues, marker removal, transcript parity, and deterministic build-time work.
```

## Verify

- `swift test --package-path app/Atelier --filter AgentResponsesTests.markdownCallout --quiet` -> all callout parser and builder tests pass.
- Inspect an ordinary quote fixture -> it still parses as `.quote`.
- `git diff --check` -> no whitespace errors.
