# TASK-001 M0 app skeleton and workspace persistence

Group: M0 (foundation milestone, ships on its own)

## Brief

Goal: Build the SwiftUI app shell. Open a folder, save its path to JSON, and reload it on next launch.

Change: no app -> Atelier opens, remembers the last workspace across restarts.

How:

- Create SPM executable package [app/Atelier](app/Atelier), macOS 13+.
- Add WorkspaceState (Codable) with path, bookmark, lastOpenedAt.
- Add WorkspaceStore (ObservableObject) that loads and saves state.json in Application Support/Atelier.
- Open a folder with NSOpenPanel and make a security-scoped bookmark.
- On launch, resolve the bookmark and start the security scope. Fall back to empty state if stale.
- Root view shows empty state or the workspace name. Full steps in [M0.md](M0.md).

Files:

- [app/Atelier/Package.swift](app/Atelier/Package.swift) (executable target)
- [app/Atelier/Sources/Atelier/WorkspaceState.swift](app/Atelier/Sources/Atelier/WorkspaceState.swift) (model)
- [app/Atelier/Sources/Atelier/WorkspaceStore.swift](app/Atelier/Sources/Atelier/WorkspaceStore.swift) (persist and resolve)
- [app/Atelier/Sources/Atelier/OpenFolder.swift](app/Atelier/Sources/Atelier/OpenFolder.swift) (NSOpenPanel)
- [app/Atelier/Sources/Atelier/ContentView.swift](app/Atelier/Sources/Atelier/ContentView.swift) (empty state and workspace view)
- [app/Atelier/Sources/Atelier/AtelierApp.swift](app/Atelier/Sources/Atelier/AtelierApp.swift) (entry, selftest hook)

Expected result:

- swift build succeeds.
- A --selftest mode proves save, reload, bookmark resolve, and clear.
- The GUI app launches without crashing.

## Verify

- cd app/Atelier && swift build -> ok (build complete).
- .build/debug/Atelier --selftest -> SELFTEST: ALL PASS.
- Launch .build/debug/Atelier, confirm the process stays alive and shows a window.
