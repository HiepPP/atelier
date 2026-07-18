# Atelier

Atelier is a native macOS IDE for browsing, editing, running, and reviewing a local workspace. It targets macOS 26 and uses Swift 6.2 with strict concurrency.

## Features

- Lazy native file tree with ignored-path filtering and inline item creation.
- Editable, syntax-highlighted file tabs with per-file word wrapping.
- Embedded multi-tab SwiftTerm terminals.
- Git status, diff, staging, commit, and branch controls.
- Workspace restoration and security-scoped folder access.
- Concurrent workspaces with isolated tabs, terminals, navigation, Git, agent, and palette state.
- Persistent outer workspace rail for adding and switching live sessions.
- File-system monitoring with incremental UI refreshes.
- Keyboard shortcuts, focus mode, zoom, and native window behavior.

## Architecture

SwiftUI owns application composition, workspace layout, tabs, commands, settings, and observable presentation state. AppKit owns the file outline, editor surface, terminal rendering, panels, windows, focus, cursor, and tracking behavior.

Small `NSViewRepresentable` adapters connect both layers:

```text
SwiftUI intent -> feature model -> service -> state update -> render
SwiftUI state -> representable -> AppKit controller -> native view
AppKit event -> controller callback -> feature state update
```

Main state owners:

| State | Owner |
|---|---|
| Application lifecycle, ordered workspace catalog, and active selection | `AppModel` |
| Isolated workspace resources, models, terminals, and file watching | `WorkspaceSession` |
| File content and wrap mode | `EditorSession` |
| Open file and terminal tabs | `TerminalTabsModel` |
| Git status and operations | `GitWorkspaceModel` |
| Terminal process and native view | `TerminalController` |
| Window and global shortcut behavior | `WindowController` |

Side effects stay behind focused services for persistence, workspace access, file loading, file watching, Git, and terminal processes. Long-lived tasks and native resources have explicit cancellation paths.

The persisted app catalog stores ordered workspace identity, folder access data, and the selected workspace. Each live `WorkspaceSession` owns its runtime state and security-scoped access. Switching changes selection only, so inactive terminals and watchers stay alive. Tabs, terminals, navigation, Git presentation, agents, and palette state remain session-only and are not restored after app termination.

## Project Structure

```text
app/Atelier/
|-- Package.swift
|-- Packaging/
|-- Resources/
|-- Sources/Atelier/
|   |-- App/
|   |-- Commands/
|   |-- Editor/
|   |-- FileTree/
|   |-- Git/
|   |-- Platform/
|   |-- Settings/
|   |-- Shared/
|   |-- Terminal/
|   |-- Theme/
|   `-- Workspace/
|-- Tests/AtelierTests/
`-- scripts/
```

`Vendor/Luminare/` contains the pinned local Luminare package. Generated `.build/` and `dist/` directories are not tracked.

## Requirements

- macOS 26 or newer.
- Xcode and Swift 6.2 toolchain.
- Optional Apple signing identity for stable installed-app permissions.

## Build and Test

Run commands from the repository root:

```bash
swift build --package-path app/Atelier
swift test --package-path app/Atelier
app/Atelier/.build/debug/Atelier --selftest
```

The test target covers models, path handling, Git parsing, persistence, and file loading. The packaged self-test also checks Git operations and async file saving.

## Run and Package

```bash
app/Atelier/scripts/build_and_run.sh run
app/Atelier/scripts/build_and_run.sh --verify
app/Atelier/scripts/build_and_run.sh --release
```

`run` builds, signs, installs, and launches Atelier. `--verify` confirms the installed process starts. `--release` creates `app/Atelier/dist/Atelier.app`.

The packaging script generates `AppIcon.icns` from `Resources/AppIcon.iconset`. It uses an Apple signing identity when available and falls back to ad hoc signing.
