# TASK-010 Link And Outline Progress

Group: standalone

## Brief

Goal: Quiet link styling and add one honest reading-position cue to the outline rail.

Change: Full-strength permanent underlines and no position cue -> soft links plus a passive progress hairline.

How:

- Update link and outline behavior in [DESIGN.md](../../DESIGN.md) before code.
- Run GitNexus impact for `MarkdownSelectableDocumentView.makeNSView`, `MarkdownSelectableDocumentView.Coordinator`, and `MarkdownDocumentOutline`.
- Set normal links to accent text with an accent underline at `0.35` alpha.
- Raise only the hovered link underline to full strength.
- Keep the link pointer cursor and native link activation.
- Reuse the existing scroll bounds observer.
- Derive a clamped zero-to-one reading fraction from current and maximum scroll positions.
- Report progress only when its visible rail-pixel value changes.
- Draw a one-pixel accent hairline on the outline rail leading edge.
- Disable animation during passive scroll.
- Add link-attribute and progress-policy tests.

Files:

- [DESIGN.md](../../DESIGN.md) (link hover and progress contract)
- [app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift](../../app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift) (link hover and existing scroll observer)
- [app/Atelier/Sources/Atelier/Editor/FilePreview.swift](../../app/Atelier/Sources/Atelier/Editor/FilePreview.swift) (progress state and outline hairline)
- [app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift](../../app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift) (link and progress coverage)

Expected result:

- Links stay quiet until hover, then show a full-strength underline.
- Link hover keeps the pointing-hand cursor.
- The outline rail shows current document progress.
- Passive scrolling adds no observer and no animation.
- Progress updates do not rebuild the attributed document.

Prompt:

```text
Use $swiftui-expert-skill. Update DESIGN.md first, then set links to accent text with a 0.35-alpha underline and full underline only on hover. Keep the pointer cursor. Add a one-pixel outline reading-progress hairline from the existing scroll observer, quantize reports to visible rail pixels, add no observer, animate nothing during passive scroll, and never rebuild the document for progress.
```

## Verify

- `swift test --package-path app/Atelier --filter AgentResponsesTests.markdownLinkAndProgress --quiet` -> link and progress tests pass.
- Existing outline-selection tests -> remain green.
- Source inspection -> only the existing bounds observer drives progress.
- `git diff --check` -> no whitespace errors.
