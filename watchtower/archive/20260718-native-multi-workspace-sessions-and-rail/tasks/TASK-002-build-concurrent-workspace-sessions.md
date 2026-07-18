# TASK-002 Build concurrent workspace sessions

Group: A (contract, state engine, and workspace rail ship as one feature)

## Brief

Goal: Replace the single-session app model with a catalog of isolated live sessions. Keep resource ownership and cleanup deterministic.

Change: Activating a workspace stops the previous session -> activating a workspace selects or creates one session without stopping others.

How:

- Use `/solve` to trace current workspace activation, access, persistence, and cleanup paths.
- Run required impact analysis before changing each symbol.
- Add one Codable app-level catalog near `WorkspaceState`.
- Store ordered workspace states and the selected workspace identity.
- Decode the existing single `WorkspaceState` JSON as a legacy catalog with one item.
- Make security-scoped access live for each open session until that session closes.
- Let `AppModel` own the ordered sessions and active selection on `MainActor`.
- Restore saved workspaces independently so one missing folder does not block the others.
- Reuse an existing session when the same standardized path is selected again.
- Switch by changing selection only. Do not stop terminals, watchers, Git, agents, or palettes.
- Close only the active session, release its resources, then select a stable remaining session.
- Stop every session and release every resource during app shutdown.
- Add focused tests for migration, duplicate selection, isolation, switching, failure, close, and shutdown.
- Extend self-test coverage for the new persistence shape and legacy decode path.

Files:

- [app/Atelier/Sources/Atelier/App/AppModel.swift](app/Atelier/Sources/Atelier/App/AppModel.swift) (own live sessions and active selection)
- [app/Atelier/Sources/Atelier/App/AppEnvironment.swift](app/Atelier/Sources/Atelier/App/AppEnvironment.swift) (provide multi-session access ownership when needed)
- [app/Atelier/Sources/Atelier/App/SelfTest.swift](app/Atelier/Sources/Atelier/App/SelfTest.swift) (verify catalog persistence and migration)
- [app/Atelier/Sources/Atelier/Workspace/Models/WorkspaceState.swift](app/Atelier/Sources/Atelier/Workspace/Models/WorkspaceState.swift) (define the persisted catalog shape)
- [app/Atelier/Sources/Atelier/Workspace/Services/WorkspaceAccessController.swift](app/Atelier/Sources/Atelier/Workspace/Services/WorkspaceAccessController.swift) (hold independent security-scoped access)
- [app/Atelier/Sources/Atelier/Workspace/Services/WorkspacePersistenceService.swift](app/Atelier/Sources/Atelier/Workspace/Services/WorkspacePersistenceService.swift) (save the catalog and decode legacy state)
- [app/Atelier/Sources/Atelier/Workspace/State/WorkspaceSession.swift](app/Atelier/Sources/Atelier/Workspace/State/WorkspaceSession.swift) (preserve per-session resources and cleanup)
- [app/Atelier/Tests/AtelierTests/WorkspaceLifecycleTests.swift](app/Atelier/Tests/AtelierTests/WorkspaceLifecycleTests.swift) (add focused multi-workspace lifecycle tests)

Expected result:

- Several workspaces stay alive during one Atelier session.
- Each workspace owns distinct tabs, terminals, navigation, Git, agent, and palette state.
- Selecting a duplicate path reuses its existing session.
- A failed restore leaves an unavailable catalog item and keeps valid sessions usable.
- Closing or quitting releases only the intended resources.
- Existing single-workspace saved data restores without user action.

Prompt:

```text
Use /solve for this multi-file lifecycle change. Map activation, persistence, security-scoped access, and cleanup before editing. Follow required GitNexus impact checks for every modified symbol. Implement the smallest MainActor session catalog that preserves WorkspaceSession ownership. Keep inactive sessions running. Add deterministic migration, isolation, duplicate, failure, close, and shutdown tests. Do not build UI in this TASK.
```

## Verify

- `swift build --package-path app/Atelier` -> the new state engine builds under strict concurrency.
- `swift test --package-path app/Atelier` -> lifecycle, persistence, migration, and existing tests pass.
- `app/Atelier/.build/debug/Atelier --selftest` -> the catalog and legacy state paths pass.
- Inspect two sessions after switching -> their `TerminalTabsModel` instances and selected tabs remain distinct.
- Inspect cleanup tests -> closing one session does not stop another session.
- Inspect duplicate tests -> standardized duplicate paths produce one live session.
