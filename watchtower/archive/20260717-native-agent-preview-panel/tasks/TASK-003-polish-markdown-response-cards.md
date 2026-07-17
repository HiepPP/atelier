# TASK-003 Polish Markdown Response Cards

Group: B (native response panel vertical slice)

## Brief

Goal: Make long agent answers easy to scan and copy. Preserve source order while improving common Markdown blocks and timeline behavior.

Change: Basic Markdown cards -> polished reading cards with bounded rich blocks.

How:

- Refine card spacing, type scale, provider accents, metadata, and visual hierarchy.
- Keep heading, paragraph, quote, divider, ordered list, and unordered list order exact.
- Add clear language labels and copy actions to fenced code blocks.
- Add compact table rendering with horizontal overflow inside the panel.
- Keep inline links selectable and open them through normal macOS behavior.
- Bound very large blocks without hiding the original response source.
- Avoid forced scrolling when the user is reading an older response.
- Show a new-response affordance when fresh content arrives below the viewport.
- Keep text selection and copy behavior available across every text block.
- Add parser tests for mixed blocks, tables, fences, and malformed Markdown.

Files:

- [app/Atelier/Sources/Atelier/Agent/AgentMarkdownView.swift](app/Atelier/Sources/Atelier/Agent/AgentMarkdownView.swift) (Markdown block model, responsive block views, tables, and code actions)
- [app/Atelier/Sources/Atelier/Agent/AgentResponsesView.swift](app/Atelier/Sources/Atelier/Agent/AgentResponsesView.swift) (card chrome, timeline scrolling, and new-response affordance)
- [app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift](app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift) (Markdown order, table, fence, and fallback tests)

Expected result:

- Mixed Markdown keeps its source order and remains readable at both panel widths.
- Code blocks show their language and copy complete bounded content.
- Wide tables scroll inside their card instead of widening the workspace.
- New responses do not pull the reader away from older content.
- All visible prose and source text remains selectable.

## Verify

- `swift test --package-path app/Atelier --filter AgentResponsesTests` -> all Markdown parsing and card-state tests pass.
- Preview headings, lists, quotes, code, tables, links, and dividers at narrow width -> no horizontal workspace overflow appears.
- Scroll to an older response, then append a fixture response -> position stays stable and the new-response affordance appears.
- Activate each code copy action -> the copied source matches the fenced block.
