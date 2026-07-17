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
