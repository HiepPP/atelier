# TASK-002 Nested List Depth

Group: standalone

## Brief

Goal: Preserve up to three Markdown list depths. Make nested structure clear without adding layout-time work.

Change: Trimmed flat list items -> depth-aware list blocks with a visible marker ladder.

How:

- Update the nested-list contract in [DESIGN.md](../../DESIGN.md) before code.
- Run GitNexus impact for `AgentMarkdownBlock`, `AgentMarkdownBlock.parse`, `appendListItem`, and `AgentMarkdownView.listRow`.
- Count leading spaces before trimming each candidate list line.
- Compute `depth = min(3, spaces / 2)` for unordered, ordered, and task items.
- Store depth on all three list block cases and preserve it through lazy continuation.
- Use filled bullet, ring, then dash markers for unordered depths zero through two.
- Multiply the marker gutter and explicit tab stop by depth.
- Keep wrapped item lines on the same text indent.
- Fade marker color from accent toward border by depth.
- Apply matching depth structure in the transcript renderer.
- Add parser, continuation, and native paragraph-style tests.

Files:

- [DESIGN.md](../../DESIGN.md) (nested-list contract)
- [app/Atelier/Sources/Atelier/Agent/AgentMarkdownView.swift](../../app/Atelier/Sources/Atelier/Agent/AgentMarkdownView.swift) (depth-aware block cases, parser, and transcript lists)
- [app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift](../../app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift) (native gutters, markers, and tab stops)
- [app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift](../../app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift) (depth and wrapping coverage)

Expected result:

- A three-level list renders as three clear nested columns.
- Depth never exceeds three.
- Wrapped lines align with item text, not their marker.
- Existing flat, ordered, and task lists keep current meaning.

Prompt:

```text
Use $swiftui-expert-skill. Update DESIGN.md first, then preserve nested list depth. Capture leading spaces before trim, add depth to unorderedItem, orderedItem, and taskItem, cap depth at 3, use a filled bullet, ring, and dash ladder, multiply gutter and tab stops by depth, keep wrapped text aligned, fade marker color from accent to border, and do no layout-pass math.
```

## Verify

- `swift test --package-path app/Atelier --filter AgentResponsesTests.markdownNestedList --quiet` -> depth, continuation, and cap tests pass.
- Inspect paragraph styles for all three depths -> tab stops and wrapped indents match.
- `git diff --check` -> no whitespace errors.
