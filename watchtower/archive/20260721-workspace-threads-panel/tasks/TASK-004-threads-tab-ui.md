# TASK-004 Workspace group thread rows

Group: B (threads panel implementation)

## Brief

Goal: Render thread rows inside each workspace group in the left Workspace panel. Clicking a workspace header activates its project. Clicking a nested thread activates its project and focuses the matching terminal.

Change: Workspace panel has flat workspace rows -> each workspace group has its own header and nested agent-thread rows. Sidebar stays Explorer and Git only.

How:

- Keep `WorkspaceSidebarTab` limited to Explorer and Git. Remove any `.threads` case and sidebar body branch from the first implementation.
- Keep the existing Workspaces header. Do not add a Threads tab or separate panel body.
- Turn each workspace list item into a group. Keep the existing 44-point workspace header as its own click, drag, drop, and context-menu target.
- Render that workspace's thread rows directly below its header. Each nested thread has its own click target and never triggers the workspace-header action.
- Add a small thread-row view in a focused file under [app/Atelier/Sources/Atelier/Workspace/Views/](app/Atelier/Sources/Atelier/Workspace/Views/). Read thread values from the parent workspace group:
  - One row per `ThreadEntry`: a status dot (running uses the accent or green, done uses a quiet gray), the agent name, and a trailing relative time shown only for done rows, computed from `finishedAt`.
  - When a group has no threads, show one quiet row "No threads yet".
  - Use `rowHeight` 28, an indented shared selection pill, and `atelierPointerCursor()` on each clickable row.
- Refresh from a `.task` on `WorkspaceRailView`: build snapshots with `app.threadsPanel.makeSnapshots(sessions: app.liveSessions)`, call `app.threadsPanel.refresh(snapshots:now:)`, then sleep about 2 seconds. Cancel when the rail disappears. Skip refresh while the app is inactive if existing scene state is available without broad changes.
- Update the done-row relative time about once a minute with a light `TimelineView(.periodic)` or by recomputing on each 2 second tick. Do not store the formatted string in the model.
- Click a row: activate the row's workspace through the same activation path the rail uses, then set the workspace `terminalTabs` selected id to the row `terminalID` and focus it. Read [app/Atelier/Sources/Atelier/Workspace/Views/WorkspaceRailView.swift](app/Atelier/Sources/Atelier/Workspace/Views/WorkspaceRailView.swift) and [app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift](app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift) to reuse the existing activation and tab-select APIs. Run impact analysis on any activation method you call.

Files:

- [app/Atelier/Sources/Atelier/Workspace/Views/ContentView.swift](app/Atelier/Sources/Atelier/Workspace/Views/ContentView.swift) (keep the sidebar limited to Explorer and Git; remove the first implementation's `.threads` case and branch)
- [app/Atelier/Sources/Atelier/Workspace/Views/WorkspaceRailView.swift](app/Atelier/Sources/Atelier/Workspace/Views/WorkspaceRailView.swift) (group each workspace header with its nested thread rows; own gated refresh)
- [app/Atelier/Sources/Atelier/Workspace/Views/ThreadsPanelView.swift](app/Atelier/Sources/Atelier/Workspace/Views/ThreadsPanelView.swift) (new: reusable nested thread rows and click handling)

Expected result:

- The Workspace panel has no Threads tab. Each workspace group shows its nested agent threads.
- Clicking a workspace header activates only that workspace. Clicking a thread activates its workspace and selects the exact terminal.
- The sidebar still shows only Explorer and Git.
- The Workspace panel lists every live workspace as a group. Each group shows its agent terminals, or "No threads yet".
- A terminal running an agent shows a running row. When the agent exits, the row shows done with a relative time. Closing the terminal removes the row.
- Clicking a row switches to that workspace and focuses the terminal.
- Refresh work stops when the Workspace panel disappears and is skipped while the app is inactive when practical.

Prompt (optional):

```text
Use $swiftui-expert-skill. Run gitnexus_impact on WorkspaceRailView, WorkspaceRailItemButton, and any workspace-activation method before editing. Keep all mutation on MainActor. Keep workspace-header and thread-row hit targets separate. Do not switch terminal representables in and out of the hierarchy.
```

## Verify

- `swift build --package-path app/Atelier` -> builds with no error.
- `app/Atelier/.build/debug/Atelier --selftest` -> self-test passes.
- `app/Atelier/scripts/build_and_run.sh run` -> app launches. The left Workspace panel shows each workspace header with nested thread rows and no Threads tab. Explorer and Git remain in the next sidebar. Open two workspaces. Run `claude` in one terminal. Its workspace group shows that terminal as running. Exit the agent, and the row shows done with a time. Close the terminal, and the row disappears. Click another workspace header and confirm only the project changes. Click a thread in another workspace and confirm the app switches to that project and focuses the exact terminal.
- Measure idle CPU with `ps -p PID -o %cpu=`. It stays in the 0.2-2% range while the active Workspace panel refreshes. Sustained CPU means an invalidation loop; profile with `sample PID 3`.
