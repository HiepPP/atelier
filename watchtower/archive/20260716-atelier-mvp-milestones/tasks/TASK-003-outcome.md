# TASK-003 Outcome

## Outcome

Status: BLOCKED

Changed:
- Added SwiftTerm 1.14.0 to the app package.
- Added retained terminal sessions with add, switch, and close controls.
- Started each shell as a login shell at the workspace path.

Contract:
- Each tab owns an independent `LocalProcessTerminalView` and shell process.
- Switching panels keeps terminal instances alive.
- Closing a tab terminates only that tab, including teardown cleanup.

Verified:
- `cd app/Atelier && swift build` -> SwiftTerm resolved at 1.14.0 and build completed.
- Native executable launch -> process stayed alive; `pwd`, resize, and two-tab interaction were not automated.
- Resumed Computer Use check against the signed app path and bundle ID -> failed before terminal interaction.

Blocked:
- Signed `.app` bundle is ready, but Computer Use authentication blocks the two-tab shell checks.
