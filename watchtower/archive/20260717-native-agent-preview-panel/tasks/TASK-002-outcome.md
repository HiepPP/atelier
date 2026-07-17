# TASK-002 Outcome

## Outcome

Status: DONE

Changed:
- Removed Responses from `CenterTabContent` and `TerminalTabsModel`.
- Added workspace-owned preview visibility state with open, toggle, and close actions.
- Added a resizable docked panel, trailing narrow overlay, compact session picker, and no-selection state.
- Added responder capture and restoration through the existing `WindowController`.

Contract:
- SwiftTerm remains mounted and authoritative while the preview opens, closes, or changes layout.
- The preview never sends terminal input and never mutates terminal buffer state.
- Widths at or above 1,400 points dock the panel; narrower widths overlay it.
- Only response cards that become visible are marked read.

Verified:
- Layout and width-bound policy tests passed at 1,000 and 1,600 point widths.
- Computer Use confirmed narrow overlay and wide dock layouts while `Terminal 1` stayed mounted.
- Computer Use changed the accessible dock width from 448 to 496 points.
- Computer Use confirmed terminal input after closing the preview with `RESTORE_CHECK`.
- Live Codex and Claude TUI responses stayed visible and interactive beside the populated preview.
- `rg -n "Mermaid|AgentResponse|AgentPreview" app/Atelier/Sources/Atelier/Terminal/TerminalController.swift` returned no matches.
