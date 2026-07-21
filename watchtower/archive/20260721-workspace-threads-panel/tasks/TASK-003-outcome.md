# TASK-003 Outcome

## Outcome

Status: DONE

Changed:
- Added thread status, entry, workspace group, and terminal snapshot value types.
- Added a MainActor observable model with a terminal-id run-state map.
- Added live snapshot creation and pure deterministic grouping.
- Assigned groups only when their Equatable value changes.
- Added one app-level `ThreadsPanelModel` owner.

Verified:
- Model tests cover running, idempotent refresh, done, removal, and empty groups.
- `swift build --package-path app/Atelier` -> passed.
- `swift test --package-path app/Atelier` -> 188 tests in 21 suites passed.
- `app/Atelier/.build/debug/Atelier --selftest` -> all checks passed.
