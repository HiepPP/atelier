# TASK-007 Optical Quote And List Markers

Group: standalone

## Brief

Goal: Add restrained print-typography detail to native quotes and list markers.

Change: Plain quote gutter and geometric marker alignment -> hanging quote glyph and optical outdent.

How:

- Update the optical-alignment contract in [DESIGN.md](../../DESIGN.md) before code.
- Run GitNexus impact for `MarkdownPreviewLayoutManager.drawBackground` and `appendListItem`.
- Add one large serif opening quote glyph beside the existing blockquote bar.
- Use the accent color at `0.18` alpha.
- Resolve and cache the glyph run before drawing.
- Store required glyph and color data in `MarkdownPreviewDecorationMetrics`.
- Draw no new color, font, path, or attributed string allocation during layout.
- Shift list markers about one point into the gutter.
- Keep the text tab stop and wrapped-line indent unchanged.
- Add pixel and paragraph-style tests.

Files:

- [DESIGN.md](../../DESIGN.md) (hanging glyph and optical alignment)
- [app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift](../../app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift) (cached decoration and marker positioning)
- [app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift](../../app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift) (pixel and indent coverage)

Expected result:

- Quotes show one quiet hanging opening mark beside the existing rule.
- Soft-wrapped quotes keep one continuous bar and one glyph.
- List markers read flush with surrounding prose.
- List text and wrapped lines keep their current alignment.

Prompt:

```text
Use $swiftui-expert-skill. Update DESIGN.md first, then add a large cached serif opening quote glyph in the quote gutter at accent 0.18 alpha. Draw it beside the existing bar, precompute its glyph run, add about one point of list-marker optical outdent, keep text tab stops unchanged, and allocate nothing in draw or layout.
```

## Verify

- `swift test --package-path app/Atelier --filter AgentResponsesTests.nativeMarkdownOpticalMarkers --quiet` -> pixel and indent tests pass.
- Existing blockquote bar and task-item styling tests -> remain green.
- `git diff --check` -> no whitespace errors.
