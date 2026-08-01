# TASK-010 Render inline code without a fill

Group: A
Class: risky

## Brief

Goal: Stop a code-heavy paragraph from reading as a mosaic. Remove the inline code fill, the
horizontal reservation, and the draw path that paints the fill.

Change: inline code becomes JetBrains Mono at `0.92` of body size in primary ink. Nothing else.

Measured evidence: fill `#D5D0C9` on a `#F8F7F4` page, and a 12 point kern on both sides of every
run. That kern is why a full stop after `tokens@^4.0.0` floats away from it, and why a short word
between two runs reads as its own box.

How:

- In `inlineText` in
  [app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift](app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift),
  stop adding `.atelierInlineCode` and stop adding the two `.kern` reservations around a code run.
  Keep the `.font` swap to the code font and set the foreground to
  `AppKitThemeAdapter.foreground`.
- Size the inline code font at `0.92` of the surrounding run's point size, snapped to display scale.
  It currently inherits the shared code font, which is sized for fenced blocks.
- Remove the fill drawing for `.atelierInlineCode` from `MarkdownPreviewLayoutManager`, and remove
  the now-unused `inlineCodePadding` and `inlineCodeHorizontalReservation` from
  `MarkdownPreviewDecorationMetrics`.
- Delete `MarkdownInlineCodeLayout`, and delete `AgentMarkdownInlinePolicy.pureCodeContent`, which
  has had no callers since the SwiftUI renderer was removed.
- Match `AgentMarkdownInlinePolicy.cachedAttributedString` in
  [app/Atelier/Sources/Atelier/Agent/AgentMarkdownView.swift](app/Atelier/Sources/Atelier/Agent/AgentMarkdownView.swift):
  no background, primary ink.
- Leave the table cell code path alone apart from the fill. With no fill there is nothing to
  fragment across wrapped lines, so the wrapped-path defect resolves itself. Confirm that by reading
  the cell path; do not add a new treatment.
- Keep the color-swatch behavior for hex tokens inside code runs.
- Keep fenced code cards exactly as they are. This TASK touches inline runs only.

Files:

- [app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift](app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift):
  change `inlineText`, remove the fill draw path, remove two metrics fields, delete
  `MarkdownInlineCodeLayout`.
- [app/Atelier/Sources/Atelier/Agent/AgentMarkdownView.swift](app/Atelier/Sources/Atelier/Agent/AgentMarkdownView.swift):
  match the cached inline path, delete `pureCodeContent`.
- [app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift](app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift):
  replace `markdownInlineCodeNeutralFill`, which asserts a fill that will no longer exist.

Expected result:

- Inline code carries the code face and primary ink, with no background attribute and no kern.
- A full stop after a code run sits tight against it.
- A wrapped path inside a table cell shows no chip fragments.
- Fenced code cards are unchanged.

Prompt:

```text
The old test markdownInlineCodeNeutralFill asserts the raised fill this TASK removes.
Rewrite it as markdownInlineCodeHasNoFill: assert the run carries the code font and primary ink,
and that it carries neither a background attribute nor a kern attribute.
Do not delete the test without a replacement.
```

## Verify

- `rg -n "atelierInlineCode|MarkdownInlineCodeLayout" app/Atelier/Sources/Atelier/` -> no match.
- `swift test --package-path app/Atelier --filter markdownInlineCodeHasNoFill` -> the replacement
  test passes. It asserts the code run carries the code face and primary ink, and carries no
  background and no kern.
- `swift test --package-path app/Atelier --filter markdownTableBlocks` -> still passes.
- `swift build --package-path app/Atelier` -> build succeeds with no new warnings.
- `swift test --package-path app/Atelier` -> all tests pass.
- Visual, drivable without a plugin: capture the window per
  [watchtower/tasks/TASK-008-outcome.md](watchtower/tasks/TASK-008-outcome.md) and confirm no grey
  block appears behind an inline code run, and that a full stop after a code run sits tight.
