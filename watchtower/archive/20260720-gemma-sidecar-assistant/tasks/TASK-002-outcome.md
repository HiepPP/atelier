# TASK-002 Outcome

## Status

DONE

## Changed

New directory `app/Atelier/Sources/Atelier/Agent/Sidecar/`:

- `SidecarServices.swift` - `GemmaSidecarTabContext`, `SidecarQuickAction`,
  `@MainActor struct SidecarServices` (the shared read-only surface), and the pure
  `GemmaSidecarContextComposer` (contextBlock / compose).
- `GemmaSidecarModel.swift` - `@MainActor @Observable GemmaSidecarModel` owning its
  own interactive `GemmaAgentModel` + runtime, a separate background runtime driven
  by a serialized `SidecarBackgroundRunner` actor, the six feature instances, the
  built `SidecarServices`, `context`, `allQuickActions(for:)`, `start()/stop()`,
  `handleCommandFinished(exitCode:)`, and `clear()` (interactive session only).
- `GemmaSidecarView.swift` - container replacing the inspector body; compact header,
  feature slots, quick-action row, streaming response area (reuses
  `AgentMarkdownView` + `GemmaTranscriptScrollAnchor` + scroll chrome), prompt field
  with stop/send/clear, empty state when no tab.
- Six feature stub files (SidecarTerminalActions, TerminalGuardianFeature,
  ClaudeBriefingFeature, SessionJournalFeature, IntentGuardFeature,
  PrecommitWhisperFeature): compiling no-op models + EmptyView views, each with a
  TASK doc-comment and the exact SidecarServices members to use.

Shared-file edits (Foundation only):

- `GemmaAgentModel.swift` - added `contextProvider` so the runtime prompt gets the
  context block prepended while the transcript keeps the raw user text; chat tab
  behavior unchanged (nil provider).
- `Terminal/TerminalTabs.swift` - `selectedSidecarContext`,
  `selectedTerminalScrollback(lines:)`, and `setTerminalCommandFinishedHandler(_:)`
  plumbing; installs the handler on current and future terminals.
- `Editor/EditorSession.swift` - `selectedText` (bounded) for the selection context.
- `Workspace/State/WorkspaceSession.swift` - owns `gemmaSidecar`; `start()/stop()`
  wired.
- `Workspace/Views/ContentView.swift` - inspector injection now
  `GemmaSidecarView(model: session.gemmaSidecar)`; removed the dead
  `WorkspaceInspectorView`.

Tests:

- `Tests/AtelierTests/GemmaSidecarContextTests.swift` - context-block building for
  no-tab, file, git diff, terminal, editor selection present/blank, and prepend order.

## Contract

Inspector body is the context-aware Gemma sidecar. A context block (tab kind, file
path, working directory, git diff target, editor selection) is prepended to each
user prompt via `GemmaSidecarModel` -> `GemmaAgentModel.contextProvider`; the runtime
system prompt is unchanged. Built-in quick actions per tab kind send one-shot prompts
through `services.runInteractive`. The sidecar uses its own runtime, separate from the
chat tab; `clear()` resets only the sidecar. Streams cancel on model dealloc and on
`WorkspaceSession.stop()`. Ollama-down shows connection-error text and never blocks the
UI. The container renders with empty feature stubs and needs no change when features
land. UI on MainActor; network/tools off MainActor; no `@unchecked Sendable`.

## Verified

- `swift build --package-path app/Atelier` clean.
- `swift test --package-path app/Atelier` - 147 tests pass, including the new
  context-block suite.
- `app/Atelier/.build/debug/Atelier --selftest` - ALL PASS.
- Layout-reentrancy rules respected: native terminal surfaces stay mounted; no
  HSplitView child add/remove; no force unwrap / try! / fatalError on view paths.
- Live GUI smoke (file-tab explain stream, Ollama-down error, narrow+wide zoom) is
  left for the integrate stage per the parallel-build workflow.
