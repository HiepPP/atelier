# TASK-006 Outcome

## Outcome

Status: BLOCKED

Changed:
- Bounded rendered diff output at 4 MB while draining full process pipes safely.
- Added watcher generation guards, dropped-event refresh, and root-change watching.
- Ensured one watcher per active workspace and cancellation during teardown.
- Added `.app` bundle metadata and a repeatable ad-hoc signed release packaging script.

Contract:
- Git work stays off the main thread and supports cancellation.
- Stale watcher callbacks cannot refresh a closed workspace.
- Renamed, deleted, and binary Git diffs render as bounded text output.

Verified:
- `cd app/Atelier && swift build` -> build complete.
- `cd app/Atelier && swift run Atelier --selftest` -> all selftests passed.
- Native idle smoke -> process stayed alive at 0.0% CPU and 69,024 KB RSS after six seconds.
- `./scripts/build-app.sh release` -> signed `dist/Atelier.app` built with valid `Info.plist` and SwiftTerm resources.
- `codesign --verify --deep --strict dist/Atelier.app` -> valid on disk.
- Signed bundle launch -> PASS. CPU reached 0.0% and RSS stabilized near 94 MB from 15 through 30 seconds.
- Large-repo interaction and renamed, deleted, and binary GUI diff checks were not automated.
- Resumed Computer Use check against the signed app path and bundle ID -> failed before app-state capture.

Blocker:
- Computer Use failed four times with `Sky Computer Use native pipe startup failed`, including after service restart.
- Service logs report `Sender process is not authenticated`; GUI checks cannot continue until host authentication is restored.
- Current retry produced the same authentication error at 2026-07-16 03:25 local time.
