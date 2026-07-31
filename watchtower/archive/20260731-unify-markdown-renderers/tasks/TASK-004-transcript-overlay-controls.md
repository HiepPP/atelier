# TASK-004 Port the Mermaid source toggle and copy control

Group: A (adds overlays to the same native surface TASK-003 mounts)

## Brief

Goal: Keep the two interactive controls the old SwiftUI card had. The code copy control already works on the native preview. The Mermaid source toggle does not exist there yet.

Change: SwiftUI card buttons -> `NSHostingView` overlays pinned to text ranges.

How:

- Read how the code copy control is pinned today. The coordinator keeps `codeCopyControls` and places them over each code header range.
- Reuse that pattern for the transcript surface so every code block keeps its copy button.
- Add a Mermaid figure control with the same approach. Pin one small control to each Mermaid figure range.
- On toggle, show the Mermaid source below the figure and hide it again on a second toggle.
- Keep the source text in the same text storage. Do not open a second view for it.
- Give both controls the pointer cursor. `AtelierGhostButtonStyle` in [app/Atelier/Sources/Atelier/Theme/AtelierComponents.swift](app/Atelier/Sources/Atelier/Theme/AtelierComponents.swift) already ends in `.atelierPointerCursor()`, so a control using that style is done. Do not apply it a second time; the repo rule forbids that.
- Reserve horizontal space in the paragraph style so a control never sits on top of text.

Files:

- [app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift](app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift) (add the Mermaid control, share the overlay placement code)

Expected result:

- Every code block in a response shows the icon-only copy control with checkmark confirmation.
- Every Mermaid figure shows a source toggle.
- The toggle reveals and hides the Mermaid source without rebuilding the whole document.
- Both controls show the pointer cursor on hover.
- The file Preview surface gains the same Mermaid toggle, which is an improvement, not a regression.

## Verify

- `swift build --package-path app/Atelier` -> build succeeds.
- `swift test --package-path app/Atelier` -> all tests pass.
- New test: toggling a Mermaid figure adds the source range, and toggling again removes it.
- `rg -n "AtelierGhostButtonStyle" app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift` -> both control types use the style, which supplies the pointer cursor.
- `rg -n "atelierPointerCursor" app/Atelier/Sources/Atelier/Theme/AtelierComponents.swift` -> `AtelierGhostButtonStyle` ends in it, so a control using the style must not apply it a second time.
