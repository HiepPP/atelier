# TASK-012 Quiet the response header controls

Group: B
Class: code

## Brief

Goal: Stop the response header from being the loudest thing on screen. It carries five solid
terracotta buttons directly above a body that this plan spent five TASKs making quiet.

Measured evidence: the header button fill samples `#AC4628`, full-strength accent, across refresh,
text smaller, text larger, width toggle, and close. See
[watchtower/tasks/TASK-008-outcome.md](watchtower/tasks/TASK-008-outcome.md).

Change: move the header controls to the quiet ghost style. Keep at most one filled accent control.

How:

- Find the header control group in
  [app/Atelier/Sources/Atelier/Agent/AgentResponsesView.swift](app/Atelier/Sources/Atelier/Agent/AgentResponsesView.swift)
  and read which style each button uses today.
- Move refresh, text smaller, text larger, and the width toggle to the existing ghost icon-button
  style. Do not invent a new style; use the one the rest of the application already uses for quiet
  icon actions.
- Decide close by the same rule: it is a dismissal, not a primary action, so it is ghost too. Leave
  no filled accent control unless one is genuinely the primary action for the panel's current state.
- Keep every existing accessibility label, help text, keyboard path, and disabled state. The text
  steppers must still disable at the ends of the scale range.
- Keep the pointer cursor. The ghost style already supplies it, so do not apply
  `.atelierPointerCursor()` a second time.
- Do not change header height, spacing, or control metrics. This is a style change only.

Files:

- [app/Atelier/Sources/Atelier/Agent/AgentResponsesView.swift](app/Atelier/Sources/Atelier/Agent/AgentResponsesView.swift):
  change the button styles in the header control group.

Expected result:

- No header control renders a solid accent fill unless it is the panel's primary action.
- Every control keeps its label, help text, disabled state, and pointer cursor.
- Header height and spacing are unchanged.

## Verify

- `rg -n "AtelierGhostButtonStyle|AtelierLuminareIconButtonStyle" app/Atelier/Sources/Atelier/Agent/AgentResponsesView.swift` -> the header controls route through a shared quiet style, which also supplies the pointer cursor.
- `swift test --package-path app/Atelier --filter AgentResponseTextSize` -> the existing text size
  tests still pass, so the steppers keep their disabled behavior.
- `swift build --package-path app/Atelier` -> build succeeds with no new warnings.
- `swift test --package-path app/Atelier` -> all tests pass.
- Visual, drivable without a plugin: capture the window and sample a header button fill. It must no
  longer read `#AC4628` at full strength.
