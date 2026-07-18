# Plan Context

## Shared Context

- Atelier currently keeps one `WorkspaceSession` in `AppModel`.
- Opening another folder stops the current session and its terminals.
- `WorkspaceAccessController` currently owns one security-scoped URL.
- `WorkspaceSession` owns tabs, navigation, Git, agents, watchers, and cleanup.
- The feature must keep several sessions alive during one app run.
- Each workspace must keep isolated tabs, terminals, navigation, Git, and agent state.
- The outer-left rail uses Slack's workspace mental model, not Slack's visual style.
- The result must stay native, dense, warm, calm, and consistent with [DESIGN.md](DESIGN.md).

## Decisions

- Persist the workspace catalog and selected workspace identity.
- Keep terminals, previews, navigation history, and other runtime state session-only.
- Decode the existing single-workspace state file for a safe migration.
- Selecting an already open path activates its existing session.
- Switching changes the active session without stopping inactive sessions.
- Closing a workspace stops only that session and selects a deterministic remaining session.
- App shutdown stops every session and releases every security-scoped resource.
- The `+` control adds or selects a local workspace through the existing folder picker.
- Do not add workspace reordering, remote sync, cloud storage, or a Slack visual clone.

## Open Decisions

- None.

## References

- [DESIGN.md](DESIGN.md)
- [README.md](README.md)
- [app/Atelier/Sources/Atelier/App/AppModel.swift](app/Atelier/Sources/Atelier/App/AppModel.swift)
- [app/Atelier/Sources/Atelier/Workspace/Models/WorkspaceState.swift](app/Atelier/Sources/Atelier/Workspace/Models/WorkspaceState.swift)
- [app/Atelier/Sources/Atelier/Workspace/Services/WorkspaceAccessController.swift](app/Atelier/Sources/Atelier/Workspace/Services/WorkspaceAccessController.swift)
- [app/Atelier/Sources/Atelier/Workspace/Services/WorkspacePersistenceService.swift](app/Atelier/Sources/Atelier/Workspace/Services/WorkspacePersistenceService.swift)
- [app/Atelier/Sources/Atelier/Workspace/State/WorkspaceSession.swift](app/Atelier/Sources/Atelier/Workspace/State/WorkspaceSession.swift)
- [app/Atelier/Sources/Atelier/Workspace/Views/ContentView.swift](app/Atelier/Sources/Atelier/Workspace/Views/ContentView.swift)
- `swift build --package-path app/Atelier`
- `swift test --package-path app/Atelier`
- `app/Atelier/.build/debug/Atelier --selftest`
- `app/Atelier/scripts/build_and_run.sh run`
