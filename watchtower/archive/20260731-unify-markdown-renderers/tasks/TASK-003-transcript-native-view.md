# TASK-003 Render the transcript with a self-sizing native view

Group: A (rewrites the body of `AgentMarkdownView`, which TASK-005 then cleans up)

## Brief

Goal: Replace the SwiftUI body of `AgentMarkdownView` with a native text view that sizes itself to its content. The five call sites keep the same call shape.

Change: one SwiftUI view per Markdown block -> one `NSTextView` per Markdown source, hosted inside the existing SwiftUI scroll views.

How:

- Add a `MarkdownTranscriptTextView` representable. Wrap a bare `NSTextView` with no `NSScrollView`.
- Set `isEditable` false, `isSelectable` true, `isVerticallyResizable` false, and `isHorizontallyResizable` false. Track the container width to the view width.
- Implement `sizeThatFits` from the layout manager used rect. This repo has shipped a bug where a fill representable collapsed without it.
- Build the attributed string with `MarkdownAttributedDocumentBuilder.build(..., presentation: .transcript)` from TASK-002.
- Cache the built document in the coordinator. Rebuild only when the source, scale, display scale, or appearance changes.
- Reuse the existing `MarkdownPreviewLayoutManager` so inline code chips, heading rules, and quote bars still draw.
- Keep `AgentMarkdownView(source:bodyFontSize:presentation:blocks:inlineRuns:)` as the public shape. Its body now returns the representable.
- Do not add a scroll view. The response panel and the chat views already scroll.

Files:

- [app/Atelier/Sources/Atelier/Agent/AgentMarkdownView.swift](app/Atelier/Sources/Atelier/Agent/AgentMarkdownView.swift) (replace the view body, keep the parser types and policies)
- [app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift](app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift) (expose the layout manager and metrics the new view needs)

Expected result:

- The response panel renders its answer through the native surface.
- Text selection runs across headings, paragraphs, lists, quotes, code, and tables in one drag.
- The card grows to the full answer height. No inner scroll bar appears inside a response card.
- The Gemma chat tab, the Gemma sidecar, the Terminal Guardian card, and the workspace search view all still render.

Prompt:

```text
Invoke $swiftui-expert-skill first. Run gitnexus impact on AgentMarkdownView before editing it and report the blast radius. Never mutate state from a layout-derived value; defer any such mutation with Task { @MainActor in ... }.
```

## Verify

- `swift build --package-path app/Atelier` -> build succeeds.
- `swift test --package-path app/Atelier` -> all tests pass.
- New test: build a long source, then assert `sizeThatFits` reports a height above the single-line height.
- `app/Atelier/scripts/build_and_run.sh run` -> the app launches and a response card shows its full answer.
