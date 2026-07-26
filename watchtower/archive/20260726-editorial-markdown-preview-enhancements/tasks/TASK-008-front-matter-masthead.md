# TASK-008 Front Matter Masthead

Group: standalone

## Brief

Goal: Open front-matter documents with their title, followed by a quiet metadata masthead.

Change: Metadata card before H1 -> H1, masthead, lede, then remaining metadata card.

How:

- Update the front-matter ordering contract in [DESIGN.md](../../DESIGN.md) before code.
- Run GitNexus impact for `MarkdownAttributedDocumentBuilder.build`, `appendFrontMatter`, and `MarkdownDocumentTypePolicy.hasLedeParagraph`.
- Detect front matter at block zero followed by H1 at block one.
- Emit the H1 before any metadata.
- Select up to three short scalar entries in source order, excluding `title`.
- Render those entries in one accent micro masthead row with hairline gaps.
- Keep remaining entries in the existing quiet metadata card below.
- Keep the first paragraph after H1 as the lede.
- Avoid another parse pass and keep heading anchor IDs stable.
- Add output-order, key-selection, lede, and fallback tests.

Files:

- [DESIGN.md](../../DESIGN.md) (masthead order and key policy)
- [app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift](../../app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift) (native builder order, masthead, and lede policy)
- [app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift](../../app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift) (order and fallback coverage)

Expected result:

- A front-matter document followed by H1 starts with its title.
- At most three short non-title values appear in the masthead.
- Remaining metadata stays available in the card.
- Documents without the front-matter plus H1 pattern keep current ordering.

Prompt:

```text
Use $swiftui-expert-skill. Update DESIGN.md first, then defer front matter when block zero is front matter and block one is H1. Render H1 first, then up to three short non-title keys in one accent micro masthead row with hairline gaps, then the lede, with remaining keys in the quiet card. Keep anchor IDs stable and add no parse pass.
```

## Verify

- `swift test --package-path app/Atelier --filter AgentResponsesTests.nativeMarkdownFrontMatterMasthead --quiet` -> order, masthead, lede, and fallback tests pass.
- Existing front-matter parser fallback tests -> remain green.
- `git diff --check` -> no whitespace errors.
