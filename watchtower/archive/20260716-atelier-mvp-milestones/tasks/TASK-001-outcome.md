# TASK-001 Outcome

## Outcome

Status: DONE

Changed:
- Created SPM executable package app/Atelier with 5 source files.
- Added WorkspaceState, WorkspaceStore, OpenFolder, ContentView, AtelierApp.
- Added a --selftest mode that runs the persist and reload checks headless.

Contract:
- state.json lives in Application Support/Atelier and holds path, bookmark, lastOpenedAt.
- WorkspaceStore.init loads state, resolves the bookmark, and starts the security scope.
- Stale bookmark or missing folder falls back to empty state without crashing.

Verified:
- cd app/Atelier && swift build -> ok (build complete).
- .build/debug/Atelier --selftest -> SELFTEST: ALL PASS (save JSON, reload workspace, bookmark resolve, clear -> empty).
- Launched .build/debug/Atelier -> process alive, no stderr, clean shutdown.

Note:
- NSOpenPanel folder pick is a manual GUI step, not covered by selftest.
- App runs from swift run. A .app bundle with Info.plist is a later decision (see CONTEXT Open Decisions).
