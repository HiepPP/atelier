# TASK-002 Outcome

## Outcome

Status: DONE

Changed:

- Added `WorkspaceCatalogState` with ordered, deduplicated workspace identity and selected identity.
- Migrated persistence from one `WorkspaceState` to a catalog with legacy single-state decoding.
- Changed `AppModel` to own ordered states, live sessions, selection, loading state, and per-item failures.
- Gave every live session its own `WorkspaceAccessController` and deterministic cleanup.
- Added lifecycle tests for migration, duplicate selection, isolation, switching, partial restore, close, and shutdown.
- Extended self-test coverage for catalog persistence and legacy migration.
- Merged delayed startup restore into the live catalog instead of replacing user-created sessions.
- Added staged restore scheduling so loading state is observable before activation.
- Serialized app-level catalog writes and rejected stale service writes by save revision.
- Made app termination wait for the final catalog write before macOS completes quit.
- Deferred persistence until startup load and catalog merge finish.
- Released deferred writes on empty load, decode failure, cancellation, and stop.

Contract:

- Duplicate standardized paths reuse one live session.
- Switching changes selection without stopping inactive sessions.
- Missing restored folders remain in the catalog while valid sessions stay usable.
- Closing releases one session. App shutdown releases all sessions.
- Existing `AppModel.workspace` callers resolve the active session through a compatibility property.
- User catalog changes made during startup load keep their order and selected workspace.
- Closing a staged item cannot leave a live session outside the catalog.
- `AppModel.stop()` returns a completion task after the final catalog reaches persistence.
- Startup user actions never overwrite the saved catalog before restore reads it.

Verified:

- `swift build --package-path app/Atelier` passed.
- `swift test --package-path app/Atelier` passed 121 tests in 13 suites.
- `app/Atelier/.build/debug/Atelier --selftest` passed all checks.
- Delayed startup-load test preserved the user workspace and restored session with no orphan.
- Delayed out-of-order save test kept only the newest catalog.
- Delayed stop test flushed the final ordered catalog and selected workspace.
- Staged restore test observed `.loading` before workspace activation.
- Delayed startup restore test passed 20 consecutive isolated runs.
- Empty, failed, and stop-during-load tests verified every persistence gate release path.
- Main independent rerun passed the full 121-test suite after the startup gate fix.
- Direct caller analysis found medium blast radius around `AppModel.workspace` and `WorkspaceSession.stop()`; compatibility was preserved.
- GitNexus impact was unavailable because the registry has no Atelier index. Repo rules prohibit adding GitNexus metadata.
