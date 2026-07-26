# Plan Context

## Shared Context

- Build a native macOS editorial reading surface for repository documents.
- Keep the quiet print-editorial language, TextKit 1, system serif display face, and terracotta accent.
- Use the reading-surface dials: variance 4, motion 2, and density 3.
- Web rules for Tailwind, Motion, and hero sections do not apply.
- Keep typography, anti-tell, and consistency-lock rules from the supplied taste direction.
- Update [DESIGN.md](DESIGN.md) before code for every TASK.
- Keep one selectable `NSTextView`, one `NSTextStorage`, and native `Cmd-C`.
- Preserve scroll, selection, outline, page state, source content, and code-card copy content.
- Use existing design tokens only. Add no new hues.
- Keep attributed document work deterministic and cached.
- Allocate no colors, fonts, paths, or glyph runs during draw, layout, or scroll.
- Keep block-model changes compatible with transcript and file-preview consumers.
- Keep every clickable control on the Atelier pointer cursor contract.
- Run GitNexus impact analysis before editing each code symbol.
- Warn before code edits when impact risk is HIGH or CRITICAL.
- Use `$swiftui-expert-skill` for every implementation TASK.
- Do not use screenshots or Computer Use unless the user requests visual proof.

## Decisions

- Implement all ten TASKs in the supplied value order.
- Keep each TASK independently verifiable.
- Skip remote Markdown images by default.
- Resolve local image paths from the Markdown file directory.
- Preserve the existing native TextKit surface instead of adding another rendered tree.

## Open Decisions

- None.

## References

- [DESIGN.md](DESIGN.md)
- [app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift](app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift)
- [app/Atelier/Sources/Atelier/Agent/AgentMarkdownView.swift](app/Atelier/Sources/Atelier/Agent/AgentMarkdownView.swift)
- [app/Atelier/Sources/Atelier/Editor/FilePreview.swift](app/Atelier/Sources/Atelier/Editor/FilePreview.swift)
- [app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift](app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift)
