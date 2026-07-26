# TASK-005 Image Figures

Group: standalone

## Brief

Goal: Render image-only Markdown lines as stable native figures with author-provided captions.

Change: Inline image syntax or literal text -> framed figures with fixed layout and alt captions.

How:

- Update the image-figure contract in [DESIGN.md](../../DESIGN.md) before code.
- Run GitNexus impact for `AgentMarkdownBlock`, `AgentMarkdownBlock.parse`, `MarkdownAttributedDocumentBuilder.build`, and `MarkdownSelectableDocumentView.Coordinator`.
- Add an image block case with URL text and author alt text.
- Detect image-only lines before normal paragraph parsing.
- Pass an optional Markdown file directory into the native preview pipeline.
- Resolve local paths relative to that directory. Skip remote URLs by default.
- Reserve stable attachment bounds before decoding.
- Decode local images off `MainActor`, then apply the result on `MainActor`.
- Keep final attachment bounds equal to placeholder bounds to prevent scroll jumps.
- Cap the figure at `documentMaxWidth`.
- Draw a hairline border and the design-system radius.
- Render the author's alt text as the caption. Never invent a caption.
- Give transcript rendering a safe non-network fallback for the new block case.
- Add parser, path, async lifecycle, and stable-height tests.

Files:

- [DESIGN.md](../../DESIGN.md) (image policy, caption rule, and stable layout)
- [app/Atelier/Sources/Atelier/Agent/AgentMarkdownView.swift](../../app/Atelier/Sources/Atelier/Agent/AgentMarkdownView.swift) (image block parsing and transcript fallback)
- [app/Atelier/Sources/Atelier/Editor/FilePreview.swift](../../app/Atelier/Sources/Atelier/Editor/FilePreview.swift) (file-directory context)
- [app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift](../../app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift) (attachment metadata, async loading, and figure rendering)
- [app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift](../../app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift) (parser and native figure coverage)

Expected result:

- Local image-only lines render as centered figures.
- Loading completion does not change document height or scroll position.
- Remote images do not load.
- Captions equal source alt text exactly.
- Missing or invalid images retain a quiet stable placeholder.

Prompt:

```text
Use $swiftui-expert-skill. Update DESIGN.md first, then implement image-only figure blocks. Resolve local paths from the Markdown file directory, skip remote URLs, decode off main, reserve stable attachment height, cap figures at documentMaxWidth, use a hairline border and shape-lock radius, show source alt text as the caption, invent no captions, and preserve one NSTextStorage.
```

## Verify

- `swift test --package-path app/Atelier --filter AgentResponsesTests.markdownImageFigure --quiet` -> parser, path, and attachment tests pass.
- Stable-height test -> placeholder and loaded attachment use the same bounds.
- Remote URL test -> no loader request starts.
- `git diff --check` -> no whitespace errors.
