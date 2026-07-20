# Plan Context

## Shared Context

- Goal: replace the low-value static inspector sidecar with a context-aware Gemma assistant panel.
- The static inspector is `WorkspaceInspectorView` in [app/Atelier/Sources/Atelier/Workspace/Views/ContentView.swift](app/Atelier/Sources/Atelier/Workspace/Views/ContentView.swift) (around line 1316). It renders `TerminalTabInspectorContext` built in [app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift](app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift) (around line 255).
- The Gemma agent stack already exists: [app/Atelier/Sources/Atelier/Agent/GemmaAgentRuntime.swift](app/Atelier/Sources/Atelier/Agent/GemmaAgentRuntime.swift) (tool loop, streaming, 8 tool limit), [app/Atelier/Sources/Atelier/Agent/Ollama/OllamaCloudClient.swift](app/Atelier/Sources/Atelier/Agent/Ollama/OllamaCloudClient.swift) (localhost:11434, model `gemma4:cloud`), [app/Atelier/Sources/Atelier/Agent/GemmaAgentView.swift](app/Atelier/Sources/Atelier/Agent/GemmaAgentView.swift) and [app/Atelier/Sources/Atelier/Agent/AgentResponsesView.swift](app/Atelier/Sources/Atelier/Agent/AgentResponsesView.swift) (chat UI).
- Existing read-only tools in [app/Atelier/Sources/Atelier/Agent/Tools/WorkspaceToolModels.swift](app/Atelier/Sources/Atelier/Agent/Tools/WorkspaceToolModels.swift): `search_workspace`, `read_file`, `read_git_diff`.
- Sidecar prompts inject tab context (tab kind, path, working directory, selection) into the user message. Do not change the runtime system prompt.
- The sidecar uses its own `GemmaAgentRuntime` instance, separate from the Gemma chat tab.
- All new tools stay read-only. No file writes, no shell execution, no automatic Git actions.
- Background features (Guardian, Journal, Intent Guard, Whisper) run one bounded Gemma call at a time. They must be cancellable and must pause when Ollama is unreachable.
- Keep UI state on `MainActor`. Keep network and tool execution off `MainActor`. No `@unchecked Sendable`.
- Follow SwiftUI crash rules in [CLAUDE.md](CLAUDE.md): no state mutation from layout pass, keep native surfaces mounted, no force unwrap on view paths.

## Decisions

- Replace the inspector body, keep a compact header (icon, title, status).
- Quick actions are one-shot prompts. Long chats stay in the Gemma tab.
- Order: design contract, sidecar panel, terminal tool, then features on top.

## Open Decisions

- None.

## References

- [DESIGN.md](DESIGN.md)
- [app/Atelier/Sources/Atelier/Terminal/TerminalController.swift](app/Atelier/Sources/Atelier/Terminal/TerminalController.swift)
- `swift build --package-path app/Atelier`
