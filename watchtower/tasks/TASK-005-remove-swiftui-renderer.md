# TASK-005 Delete the SwiftUI block renderer

Group: A (removes the code TASK-003 replaced, so it runs last in the group)

## Brief

Goal: Remove the dead SwiftUI block rendering code and migrate the one test that depends on it. Only one renderer stays in the repo.

Change: two renderers -> one renderer plus shared parser and policy types.

How:

- Delete the SwiftUI block rendering members of `AgentMarkdownView`: `blockStack`, `blockView`, `heading`, `codeBlock`, `table`, `tableGrid`, `tableCell`, `listRow`, `frontMatter`, `listMarker`, `inlineText`, `headingSize`, `headingWeight`, `headingDesign`, and `blockTopSpacing`.
- Delete `MarkdownHighlightedCodeText` and `MermaidResponseCard` once TASK-004 covers their behavior natively.
- Delete the unused `.document` branch logic that the old preview path needed.
- Keep every shared type: `AgentMarkdownBlock`, `ParsedMarkdownDocument`, `AgentMarkdownInlinePolicy`, `MarkdownFootnotePolicy`, `MarkdownQuoteLayout`, `MarkdownCalloutKind`, `MarkdownTableAlignmentPolicy`, `MarkdownFrontMatterLayout`, `MarkdownOutlineEntry`, `MarkdownHeadingOffsetStore`, and `MarkdownCopyButton`.
- Migrate the pixel test at [app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift](app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift) line 2415. It renders `AgentMarkdownView` through `ImageRenderer`, which cannot render a representable. Replace it with a builder assertion on the transcript marker color.
- Consider moving the shared parser types out of `AgentMarkdownView.swift` only if the file is left with mismatched contents. Do not do a wider file split in this TASK.

Files:

- [app/Atelier/Sources/Atelier/Agent/AgentMarkdownView.swift](app/Atelier/Sources/Atelier/Agent/AgentMarkdownView.swift) (delete the block renderer, keep the parser and policies)
- [app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift](app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift) (replace the `ImageRenderer` marker test)

Expected result:

- No SwiftUI per-block Markdown rendering code remains.
- All five former call sites still compile and render.
- The test suite covers transcript marker depth through the builder instead of a rendered bitmap.

## Verify

- `swift build --package-path app/Atelier` -> build succeeds with no unused-symbol warnings.
- `swift test --package-path app/Atelier` -> all tests pass.
- `rg -n "blockView|tableGrid|listRow|MermaidResponseCard" app/Atelier/Sources/Atelier` -> no matches.
- `rg -n "ImageRenderer\(" app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift` -> no match for the transcript marker test.
- `app/Atelier/.build/debug/Atelier --selftest` -> self-test passes.
