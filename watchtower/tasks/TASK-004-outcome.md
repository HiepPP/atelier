# TASK-004 Outcome

## Outcome

Status: DONE

## Changed

- `app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift`
- `app/Atelier/Sources/Atelier/Agent/AgentMarkdownView.swift` (transcript coordinator wiring)
- `app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift`

## Contract

Both Markdown surfaces now place the same two overlay controls over TextKit ranges.

- `MarkdownOverlayControlLayout` holds the shared geometry: `visibleCharacterRange(in:visibleRect:)`
  and `frame(for:size:anchor:in:host:)` with a `centered` anchor for a code header and a `top`
  anchor for a figure. The preview coordinator's inline math was replaced by it.
- `MarkdownCodeCopyControl` became internal and is used by both surfaces.
- `MarkdownMermaidSourceControl` is new: an icon-only toggle with a "View/Hide Mermaid source"
  label.
- `MarkdownMermaidSourceExpansion` inserts and removes the source block inside the same text
  storage. It returns `(location, delta)` so the caller can shift its stored regions.
- `MarkdownRegionShift.shifted(_:after:by:)` keeps headings, code blocks, and figure ranges valid
  after an in-place edit. The document is never rebuilt for a toggle.
- `MarkdownAttributedDocumentBuilder.mermaidSourceBlock(source:scale:displayScale:presentation:)`
  builds the revealed block, and `codeFont(scale:displayScale:presentation:)` is now shared with
  `build`.
- File Preview gained the Mermaid toggle, as the TASK expected.

## Verified

- `swift build --package-path app/Atelier` -> build complete, no errors and no warnings.
- `swift test --package-path app/Atelier` -> "Test run with 429 tests in 41 suites passed".
- New test "Toggling a Mermaid figure adds then removes its source range" -> passed. The first
  toggle reports a positive delta, marks the figure expanded, grows the storage, and puts
  "MERMAID SOURCE" and "graph TD" in it. The second toggle reports a negative delta, clears the
  expansion, and restores the original length and text.
- New test "An in-place edit shifts only the ranges after it" -> passed.
- `rg -n "atelierPointerCursor" app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift`
  -> lines 2321 and 2350: `MarkdownCodeCopyControl` and `MarkdownMermaidSourceControl`.

## Review fixes

Three review findings landed here. Two earlier deviations were withdrawn.

- Range shift boundary: `MarkdownRegionShift.shifted` guarded with `range.location > location`, but
  the source is inserted at `NSMaxRange(figure.range) + 1`, which is exactly where the next block
  starts. A code fence or heading right after a figure kept a range pointing into the inserted
  "MERMAID SOURCE" text. Both that guard and the mirror guard in
  `MarkdownMermaidSourceExpansion.shift` now use `>=`. The expansion records its own new range after
  the shift runs, so it never shifts itself.
- Pointer cursor: the explicit `.atelierPointerCursor()` was removed from `MarkdownCodeCopyControl`
  and `MarkdownMermaidSourceControl`. `AtelierGhostButtonStyle` already ends in that modifier, and
  the repo rule forbids double-applying it. A comment on each control names the style that supplies
  the cursor.
- Mermaid control reservation: the figure paragraph now carries
  `tailIndent: -MarkdownCodeCardLayout.copyControlReservation`, and
  `MarkdownMermaidFigureLayout.contentMeasure(_:)` drops the same width from the reserved, fitted,
  and render widths. The control no longer draws over the diagram, so the spec line is met instead
  of deviated from. DESIGN.md records the reservation.
- Stale figure ranges: the preview coordinator now stores `imageFigures`, shifts them with the other
  regions, and resolves a figure's current range by id in `applyImage`, `applyMermaid`, and
  `applyMermaidFailure`. A load that finishes after a toggle no longer invalidates a stale range.
- New test "An in-place edit shifts only the ranges after it" gained the boundary case: a region
  starting exactly at the edit location moves by the delta.
- New test "Expanding a Mermaid figure moves the block that follows it" -> passed. The code header
  starts at the insert location, and the shifted range still reads "SWIFT".
- New test "A Mermaid figure leaves trailing room for its source toggle" -> passed.
- `swift build --package-path app/Atelier` -> build complete.
- `swift test --package-path app/Atelier` -> "Test run with 432 tests in 41 suites passed".
- `rg -n "atelierPointerCursor" app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift`
  -> two comment matches naming `AtelierGhostButtonStyle`, which supplies the cursor for both
  controls.

## Deviations

- Visible-only materialization stays on the preview surface, which observes scrolling. The
  transcript surface materializes every control once, because one response card holds a handful of
  code blocks and figures and it has no scroll observer of its own.

## Not driven

- On-screen checks (hover cursor, checkmark confirmation, the toggle revealing and hiding source in
  the running app) were NOT driven. They need visual acceptance, which belongs to TASK-006.
