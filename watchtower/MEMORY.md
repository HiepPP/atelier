# Watchtower Memory

## Purpose

Read this file before creating or implementing Watchtower tasks in this repo.

This file holds long-term intent. It keeps task planning aligned across sessions.

## Core Intent

- Grow Atelier into a native agent control plane through small, verified slices.
- Keep Git review, workspace ownership, native focus, and predictable cleanup central.
- Start agent integration with Gemma 4 through Ollama Cloud.

## Planning Rules

- Add provider-neutral protocols only after a second provider creates a real need.
- Keep UI state on `MainActor`. Keep network and tool execution off `MainActor`.
- Give every agent task a clear cancellation and workspace cleanup path.
- Keep the first Gemma slice read-only until safety and tool-call tests pass.

## Source Anchors

- [app/Atelier/Sources/Atelier/Workspace/State/WorkspaceSession.swift](app/Atelier/Sources/Atelier/Workspace/State/WorkspaceSession.swift): owns workspace resources and cleanup.
- [app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift](app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift): owns center terminal and editor tabs.
- [app/Atelier/Sources/Atelier/Git/GitService.swift](app/Atelier/Sources/Atelier/Git/GitService.swift): provides cancellable Git process work.
- [app/Atelier/Sources/Atelier/Shared/Logging/AppLogger.swift](app/Atelier/Sources/Atelier/Shared/Logging/AppLogger.swift): defines unified logging categories.
- [app/Atelier/Sources/Atelier/Agent/Sidecar/](app/Atelier/Sources/Atelier/Agent/Sidecar/): Gemma sidecar assistant. GemmaSidecarModel owns its own interactive + background runtimes (separate from the chat-tab gemmaAgent) plus the six feature models; SidecarServices is the read-only closure surface features consume; GemmaSidecarView is the container. Add a new sidecar feature as ONE self-contained file (model + view) wired via SidecarServices and a slot in GemmaSidecarView; do not spread it across shared files.

## Verification Bias

- `swift build --package-path app/Atelier`
- `swift test --package-path app/Atelier`
- `app/Atelier/.build/debug/Atelier --selftest`
- Verify cancellation, path containment, bounded output, and sensitive-file rejection.

## Avoid

- Do not let SwiftUI views read the filesystem or call Ollama directly.
- Do not add file writes, arbitrary shell execution, or automatic Git actions in the first slice.
- Do not log prompts, file contents, tool results, or credentials by default.
- Do not weaken strict concurrency with `@unchecked Sendable` shortcuts.

## Learnings

- 2026-07-18: Keep Codex and Claude interaction in SwiftTerm. Native response UI observes transcripts and never replaces or mutates terminal state.
- 2026-07-18: Keep FocusedValue-only palette shortcuts in a separate Commands type. Mixing them into model-bearing AppCommands crashed SwiftUI during app launch.
- 2026-07-19: Persist only the ordered workspace catalog and active identity. Keep tabs, terminals, navigation, Git, agents, and palettes inside live sessions.
- 2026-07-19: Defer catalog writes until startup load merges with user changes. Serialize later writes and flush the final catalog before app termination.
- 2026-07-19: Resign the old AppKit responder when switching workspaces. Restore a responder only when its workspace owner and revision remain active.
- 2026-07-20: Sidecar features use a registry/slot pattern so each feature is one file with no shared-file edits; this let a fan-out team build six features in parallel. Background features run bounded, serialized, cancellable calls via SidecarServices.runBackground on a runtime separate from the interactive one. Terminal Guardian gets exit codes from a TerminalController OSC 133 handler (registerOscHandler code 133; no marks -> never fires). read_terminal_output bridges the actor tool executor to the MainActor SwiftTerm buffer via an injected @Sendable snapshot provider (getText/buffer.lines + BufferLine.translateToString).
