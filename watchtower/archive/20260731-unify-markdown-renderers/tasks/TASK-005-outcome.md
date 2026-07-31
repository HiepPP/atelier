# TASK-005 Outcome

## Outcome

Status: DONE

## Changed

- `app/Atelier/Sources/Atelier/Agent/AgentMarkdownView.swift`
- `app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift`

## Contract

One Markdown renderer remains. The SwiftUI per-block rendering code is gone.

Deleted from `AgentMarkdownView`: `blockStack`, `blockView`, `heading`, `codeBlock`, both `table`
overloads, `tableGrid`, `tableCell`, `listRow`, `frontMatter`, `listMarker`, `inlineText`,
`headingSize`, `headingWeight`, `headingDesign`, `blockTopSpacing`, plus the helpers only they used:
`resolvedAlignment`, `frameAlignment`, `textAlignment`, `proseLineSpacing`, `resolvedBlocks`, the
`markdownHeadingOffsetStore` environment read, and the nested `MarkdownHeadingOffsetReporter`.

Also deleted: `MarkdownHighlightedCodeText`, `MermaidResponseCard`, `MermaidRenderRequest`, the
`MarkdownListMarker` enum, the private `markdownTabularFigures` View extension, and
`MarkdownCalloutKind.swiftUIColor` (its only caller was the deleted block renderer).

Kept, as the TASK required: `AgentMarkdownBlock`, `ParsedMarkdownDocument`,
`AgentMarkdownInlinePolicy`, `MarkdownFootnotePolicy`, `MarkdownQuoteLayout`, `MarkdownCalloutKind`,
`MarkdownTableAlignmentPolicy`, `MarkdownFrontMatterLayout`, `MarkdownOutlineEntry`,
`MarkdownHeadingOffsetStore`, and `MarkdownCopyButton`. `AgentMarkdownView.swift` went from 2307 to
1495 lines.

The `ImageRenderer` pixel test was replaced. "Transcript ordered and task markers fade with nested
depth" now builds a nested ordered and task list in transcript mode and reads the marker
`foregroundColor` straight from the attributed string. It asserts each deeper marker sits closer to
the border color, which is the same fade the bitmap test measured.

## Verified

- `swift build --package-path app/Atelier` -> build complete, no errors and no unused-symbol
  warnings.
- `swift test --package-path app/Atelier` -> "Test run with 429 tests in 41 suites passed" (three
  consecutive runs).
- `rg -n "blockView|tableGrid|listRow|MermaidResponseCard|MarkdownHighlightedCodeText" app/Atelier/Sources`
  -> no matches.
- `rg -n "ImageRenderer\(" app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift` -> only line
  3167, `MermaidImageRenderer()`, which is the Mermaid renderer and not the transcript marker test.
- `app/Atelier/.build/debug/Atelier --selftest` -> "SELFTEST: ALL PASS".
- `app/Atelier/scripts/build_and_run.sh run` -> built, signed, installed, launched. PID 77966 stayed
  up at 0.4-0.6% idle CPU. No new Atelier crash report.
- `detect_changes(scope: "all")` -> 119 changed symbols across 4 files. Every affected process is a
  Markdown one (`BlockStack -> *`, `TableCell -> *`, `Update -> build`,
  `syncVisibleCodeCopyControls`). No unrelated module is touched. The reported "critical" level
  reflects change volume, not an unexpected blast radius.

## Review fixes

The review found that `AgentCodeBlockPolicy` had become dead in `Sources`: the deleted SwiftUI
renderer was its only caller, and the deletion silently dropped the transcript code-block cap. The
policy is live again. `MarkdownAttributedDocumentBuilder.appendCode` calls `displayedContent` for the
transcript body and `copiedContent` for the region source. Details and tests are in the TASK-002
outcome, because the change lands in the builder.

- `rg -n "AgentCodeBlockPolicy" app/Atelier/Sources` -> the definition plus two call sites in
  `MarkdownSelectableDocumentView.swift` (lines 1178 and 1312).
- `swift test --package-path app/Atelier` -> "Test run with 432 tests in 41 suites passed".
- `app/Atelier/.build/debug/Atelier --selftest` -> "SELFTEST: ALL PASS".

## Note

`swift test` crashed once during the run with
`WorkspaceVisibilityModel.swift:97: Fatal error: Unexpectedly found nil` (`NSApp.windows` in a
headless test host). The crash report backtrace names only `WorkspaceVisibilityModel.start` and
`.update`. It is a pre-existing flake in a file this group did not touch, and it did not reproduce
in three later runs.
