# TASK-009 Add restrained Pow feedback

Group: H (micro-interactions)

## Brief

Goal: Add small Pow effects to useful state changes without making the cockpit noisy.

Change: static status changes -> restrained completion, error, and terminal feedback

How:

- Add one app-owned motion adapter as the only Pow import boundary.
- Add a short completion effect to the Git refresh control.
- Add a short shake when a new Git error appears.
- Add a small jump when a new terminal session appears.
- Drive effects from existing model values. Do not add product state.
- Disable every Pow effect when Reduce Motion is enabled.
- Do not add particles, sound, haptics, or layout-changing transitions.

Files:

- [app/Atelier/Sources/Atelier/AtelierMotion.swift](../../app/Atelier/Sources/Atelier/AtelierMotion.swift) (single Pow boundary)
- [app/Atelier/Sources/Atelier/ChangesView.swift](../../app/Atelier/Sources/Atelier/ChangesView.swift) (refresh and error effects)
- [app/Atelier/Sources/Atelier/TerminalTabs.swift](../../app/Atelier/Sources/Atelier/TerminalTabs.swift) (new terminal feedback)

Expected result:

- Refresh completion, new errors, and new terminals give brief visual feedback.
- Effects do not move dividers, resize controls, or change actions.
- Reduce Motion removes every Pow effect.
- No feature view imports Pow directly.

## Verify

- `swift build --package-path app/Atelier` -> build completes.
- `app/Atelier/.build/debug/Atelier --selftest` -> `SELFTEST: ALL PASS`.
- `rg -l '^import Pow' app/Atelier/Sources/Atelier` -> only `AtelierMotion.swift` is returned.
- Native app with Reduce Motion off -> refresh, error, and terminal effects appear once per matching change.
- Native app with Reduce Motion on -> no Pow effect appears.
- Native narrow and wide checks -> no clipping, divider jump, or control movement.
