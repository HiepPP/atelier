# Plan Context

## Shared Context

- Atelier has two Markdown renderers today. They share one parser and differ in every block type.
- The parser is shared: `AgentMarkdownBlock.parse` and `ParsedMarkdownDocument` in [app/Atelier/Sources/Atelier/Agent/AgentMarkdownView.swift](app/Atelier/Sources/Atelier/Agent/AgentMarkdownView.swift).
- The SwiftUI renderer is `AgentMarkdownView`. It builds one SwiftUI view per block.
- The native renderer is `MarkdownAttributedDocumentBuilder` in [app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift](app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift). It builds one `NSAttributedString`.
- The SwiftUI renderer has five call sites: the response panel, the Gemma chat tab, the Gemma sidecar, the Terminal Guardian card, and the workspace search view.
- The native renderer has one call site: Markdown file Preview mode.
- Repo rule: read [DESIGN.md](DESIGN.md) first. When behavior changes, update `DESIGN.md` before the code.
- Repo rule: invoke `$swiftui-expert-skill` from [.agents/skills/swiftui-expert-skill/SKILL.md](.agents/skills/swiftui-expert-skill/SKILL.md) before writing or editing code here.
- Repo rule: every clickable control needs `.atelierPointerCursor()`.
- Repo rule: no force unwrap, `try!`, `as!`, or `fatalError` on a view or controller path.
- Repo rule: never allocate colors, fonts, or images inside a draw, layout, or per-row path.

## Decisions

- Unify on the native path. The builder plus `NSTextView` keeps images, code line numbers, the find bar, and selection across blocks. The SwiftUI path would have to rebuild all four.
- Keep the public call shape `AgentMarkdownView(source:)` so the five call sites do not change.
- Keep the Mermaid source toggle. Port it to the native surface instead of dropping it.
- Keep transcript metrics as they are today: body size 13.5, line spacing 4, tighter block gaps. Add them as a presentation mode, not as a second builder.
- The response panel keeps its own SwiftUI scroll view. The transcript text view does not scroll itself.

## Open Decisions

- None.

## References

- [app/Atelier/Sources/Atelier/Agent/AgentMarkdownView.swift](app/Atelier/Sources/Atelier/Agent/AgentMarkdownView.swift)
- [app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift](app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift)
- [app/Atelier/Sources/Atelier/Agent/AgentResponsesView.swift](app/Atelier/Sources/Atelier/Agent/AgentResponsesView.swift)
- [app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift](app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift)
- `swift build --package-path app/Atelier`
- `swift test --package-path app/Atelier`
- `app/Atelier/scripts/build_and_run.sh run`
