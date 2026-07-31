# TASK-011 Show the On This Page rail in the Response tab

Group: B
Class: code

## Brief

Goal: Use the empty space beside the answer for scanning. At a 1700 point window the response
overlay leaves about 333 points to the right of its 680 point column. Markdown Preview fills the
same region with the On This Page rail.

Change: reuse `MarkdownDocumentOutline` in the response panel, beside the answer.

How:

- `MarkdownDocumentOutline` lives in
  [app/Atelier/Sources/Atelier/Editor/FilePreview.swift](app/Atelier/Sources/Atelier/Editor/FilePreview.swift).
  Make it reachable from the response panel the same way `MarkdownStickySectionBar` was: drop
  `private`, or move it, whichever is the smaller change. Do not copy it.
- Build the entries from the answer's parsed blocks with `AgentMarkdownBlock.outline(from:)`. The
  panel already has the answer source; do not parse it a second time if the parse is already shared.
- Reuse the heading rows TASK-007 added for the active row. `AgentResponseSectionBarPolicy` already
  resolves the active title from the answer's top edge, so derive the selected entry from the same
  value instead of adding a second active-heading rule.
- Gate visibility on available width, matching `MarkdownFileDocumentPolicy.showsOutline`: show the
  rail only when the panel can hold `transcriptMaxWidth` plus `markdownOutlineWidth`. Add an
  equivalent policy for the transcript rather than reusing the document measure.
- Keep the pinned section bar and the rail in the same relationship Preview uses: the bar shows only
  when the rail is hidden. Update the bar's condition to include that.
- Crossing the width breakpoint must change opacity only. Never insert or remove a view during a
  layout pass.
- Rows use the pointer cursor on hover, which the shared component already supplies.
- Clicking a row scrolls the answer to that heading. Use the offsets the coordinator already
  reports; do not rebuild the attributed document and do not add a second scroll surface.
- Keep outline state session-only.

Files:

- [app/Atelier/Sources/Atelier/Editor/FilePreview.swift](app/Atelier/Sources/Atelier/Editor/FilePreview.swift):
  make `MarkdownDocumentOutline` shared.
- [app/Atelier/Sources/Atelier/Agent/AgentResponsesView.swift](app/Atelier/Sources/Atelier/Agent/AgentResponsesView.swift):
  add the rail, the width policy, the selection wiring, and the updated bar condition.

Expected result:

- A wide response panel shows the rail beside the answer, with the active row marked.
- A narrow response panel hides the rail and shows the pinned section bar instead.
- Clicking a row moves the answer to that heading.
- Resizing across the breakpoint does not crash and does not change the answer's measure.

## Verify

- `rg -c "struct MarkdownDocumentOutline" app/Atelier/Sources/Atelier/` -> exactly one definition.
- `swift test --package-path app/Atelier --filter transcriptOutlineVisibility` -> the new test
  passes. It asserts the rail shows at a wide panel width, hides at a narrow one, and that the bar
  and the rail are never both visible.
- `swift test --package-path app/Atelier --filter transcriptSectionBarVisibility` -> still passes.
- `swift build --package-path app/Atelier` -> build succeeds with no new warnings.
- `swift test --package-path app/Atelier` -> all tests pass.
- Visual and resize, drivable without a plugin: resize the window across the breakpoint with
  System Events, capture at each side, and confirm the rail appears and the bar swaps with it. Then
  confirm no new report in `~/Library/Logs/DiagnosticReports/`.
