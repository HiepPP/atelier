# TASK-012 Outcome

## Outcome

Status: DONE

Root cause found while reading:

- The header controls were not using a filled accent style on purpose. They used
  `.buttonStyle(.glass)`, the native Liquid Glass style, which picks up the application accent tint
  and renders an enabled control as a solid terracotta block. The previous and next chevrons only
  looked quiet in the earlier capture because they were disabled.

Changed:

- Moved all six header controls to `AtelierGhostButtonStyle()` in
  [app/Atelier/Sources/Atelier/Agent/AgentResponsesView.swift](app/Atelier/Sources/Atelier/Agent/AgentResponsesView.swift):
  previous, next, refresh, text smaller, text larger, width toggle, and close.
- Removed the explicit `.atelierPointerCursor()` from each one. `AtelierGhostButtonStyle` already
  ends in it at
  [app/Atelier/Sources/Atelier/Theme/AtelierComponents.swift](app/Atelier/Sources/Atelier/Theme/AtelierComponents.swift)
  line 454, and the repo rule bans applying it twice.

Contract:

- Every control keeps its accessibility label, help text, and disabled state. The text steppers still
  disable at the ends of the 0.8 to 1.6 range.
- The folded text-size `Menu` is unchanged. It is a `Menu`, not a `Button`, it uses
  `atelierGlassControl` rather than the accent-tinted glass button style, and it appears only when
  the header is too narrow for both steppers.
- Header height, spacing, and control metrics are unchanged. This was a style change only.

Verified:

- `rg -n "buttonStyle\\(.glass\\)" app/Atelier/Sources/Atelier/Agent/AgentResponsesView.swift` -> no
  match.
- `swift test --package-path app/Atelier --filter AgentResponseTextSize` -> 4 tests passed, so the
  steppers keep their bound behavior.
- `swift build --package-path app/Atelier` -> build complete, no new warnings.
- `swift test --package-path app/Atelier` -> 438 tests in 41 suites passed, on three consecutive
  runs at 8.479, 7.989, and 8.095 seconds.
- `app/Atelier/.build/debug/Atelier --selftest` -> `SELFTEST: ALL PASS`.

On-screen check, window 427090:

- Sampled the fill area of all five previously-filled header controls. Every one reads `#E7E3DD`,
  identical to the header chrome sampled beside them. Before this TASK the same points read
  `#AC4628`, full-strength accent.
- Read on screen: the header now shows plain glyphs with no blocks behind them, and the outline rail
  from TASK-011 renders beside the answer with its active row marked.

Note:

- `swift test` trapped twice in `WorkspaceVisibilityModel.update` at line 97, where `NSApp` is nil in
  the headless test host. This is the pre-existing flake recorded in the previous plan's LEARN.md,
  and it is unrelated to a button style change. Three consecutive runs then passed.
