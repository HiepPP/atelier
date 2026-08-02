# Context

Shared context for the plan "Menu bar appearance settings".

## What Exists Today

- [app/Atelier/Sources/Atelier/App/AtelierApp.swift](app/Atelier/Sources/Atelier/App/AtelierApp.swift)
  holds the `App` body and `AtelierZoomModel`. The zoom model owns manual zoom, the display tier,
  the sizing mode, and the agent response text scale.
- Manual zoom lives in memory only. `manualScaleByDisplay` keeps one value per display and is lost
  on quit. The sizing mode persists under `atelier.displaySizingMode`.
- `AtelierZoomModel` exposes `chromeScale`, `sidebarScale`, and `contentScale`. All three derive
  from `renderScale`, which is manual zoom times the display tier base scale.
- Text size comes from static tokens in `AtelierTypography`
  ([app/Atelier/Sources/Atelier/Theme/AtelierTheme.swift](app/Atelier/Sources/Atelier/Theme/AtelierTheme.swift)).
  `uiSize` is 14, `editorSize` is 16, `terminalSize` is 20. A view scales a token with
  `.atelierFont(size:)`, which reads the `\.atelierZoomScale` environment value.
- The terminal font is set in
  [app/Atelier/Sources/Atelier/Terminal/TerminalController.swift](app/Atelier/Sources/Atelier/Terminal/TerminalController.swift)
  by `updateScale(_:displayScale:)`, called from
  [app/Atelier/Sources/Atelier/Terminal/TerminalRepresentable.swift](app/Atelier/Sources/Atelier/Terminal/TerminalRepresentable.swift).
  Today it receives `zoom.contentScale`.
- [app/Atelier/Sources/Atelier/Settings/AtelierSettingsView.swift](app/Atelier/Sources/Atelier/Settings/AtelierSettingsView.swift)
  is the `Settings` scene. It has a Workspace section and a Resource Safety section.
- There is no menu bar item today. `rg -n "MenuBarExtra" app/Atelier/Sources` returns no match.

## Scale Contract This Plan Adds

Keep one owner for scale math: `AtelierZoomModel`. Do not add a second source of truth.

| Derived value | Formula | Used by |
|---|---|---|
| `renderScale` | `manual zoom * tier base scale` | internal only |
| `chromeScale` | `min(renderScale * appTextScale, 1.2)` | window chrome |
| `sidebarScale` | `min(renderScale * appTextScale, 1.5)` | sidebar and rail |
| `contentScale` | `renderScale * appTextScale` | panels, Git, Gemma, overlays |
| `terminalScale` | `renderScale * terminalTextScale` | terminal tabs only |
| `editorScale` | `renderScale * editorTextScale` | file tabs only |

Rules:

- App text size, terminal text size, and editor text size are independent multipliers.
- Each text scale stays between 0.8 and 1.6 and moves in 0.05 steps.
- Manual zoom keeps its current range: 0.8 to 2.0 in 0.1 steps.
- Zoom still multiplies every surface. A text scale only changes its own surface.

## Settings Keys

| Key | Type | Owner |
|---|---|---|
| `atelier.displaySizingMode` | String | exists today |
| `agentResponseTextScale` | Double | exists today |
| `atelier.appTextScale` | Double | new |
| `atelier.terminalTextScale` | Double | new |
| `atelier.editorTextScale` | Double | new |
| `atelier.manualZoomByDisplay.v1` | `[String: Double]` | new |
| `atelier.codeLigaturesEnabled` | Bool | new |
| `atelier.showsMenuBarExtra` | Bool | new |

## Rules To Honor

- Read [DESIGN.md](DESIGN.md) before code. TASK-001 updates the contract first.
- Follow `$swiftui-expert-skill` from `.agents/skills/swiftui-expert-skill/SKILL.md` for every code
  TASK in this plan.
- Every clickable control needs the pointer cursor. `AtelierGhostButtonStyle` already ends in
  `.atelierPointerCursor()`, so do not apply it twice on a control that uses that style.
- Never mutate state during an AppKit layout pass. Defer any layout-derived write with
  `Task { @MainActor in ... }`.
- Use discrete steppers, not free sliders, for the text scales. A stepper produces one mutation per
  click, so a drag cannot flood the view tree with re-renders.
- Do not allocate `NSFont` inside a draw, layout, or per-row path. `AtelierTypography.codeFont`
  caches by size; clear that cache only when the ligature setting changes.
- Keep UI state on `MainActor`.

## Verification Commands

```bash
swift build --package-path app/Atelier
swift test --package-path app/Atelier
app/Atelier/.build/debug/Atelier --selftest
app/Atelier/scripts/build_and_run.sh run
app/Atelier/scripts/atelier-doctor status --json
```

On-screen checks need a human. The `computer-use` plugin is not installed on this machine, and
`atelier-doctor probe` has no menu bar path. Report an on-screen check as a manual step.
