# TASK-002 Sidecar Gemma panel with context injection

Group: A (sidecar foundation ships as one slice)

## Brief

Goal: replace the static inspector body with a Gemma assistant panel that knows the selected tab.

Change: static label/value rows -> compact header plus quick actions, prompt field, and streaming Gemma responses.

How:

- Keep the compact header from `WorkspaceInspectorView` (icon, title, status). Remove the static detail rows.
- Add a sidecar model that owns its own `GemmaAgentRuntime` instance with the existing `OllamaCloudClient` and `WorkspaceToolExecutor`.
- Build a context block from the selected tab: tab kind, file path, git diff selection, terminal working directory, and editor selection when present. Prepend it to each user prompt. Do not change the runtime system prompt.
- Add quick actions per tab kind as one-shot prompts: file (explain this file, summarize, find usages), git diff (review this diff, suggest commit message), editor selection (explain selection).
- Reuse streaming response components from [app/Atelier/Sources/Atelier/Agent/AgentResponsesView.swift](app/Atelier/Sources/Atelier/Agent/AgentResponsesView.swift) where practical.
- Add a clear button that calls runtime reset. Cancel any running stream when the panel model deallocates or the workspace closes.
- Keep the panel usable when Ollama is down: show the existing connection error text, never block the UI.

Files:

- [app/Atelier/Sources/Atelier/Workspace/Views/ContentView.swift](app/Atelier/Sources/Atelier/Workspace/Views/ContentView.swift) (`WorkspaceInspectorView` body replaced, wiring for sidecar model)
- [app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift](app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift) (expose selected tab context for injection)
- [app/Atelier/Sources/Atelier/Agent/](app/Atelier/Sources/Atelier/Agent/) (new sidecar model file, for example GemmaSidecarModel.swift)

Expected result:

- Sidecar shows quick actions and a prompt field for file, git diff, terminal, and Gemma tabs.
- A quick action on a file tab streams an answer that cites the file path.
- Clearing resets the sidecar session without touching the Gemma chat tab.

## Verify

- `swift build --package-path app/Atelier` -> builds clean.
- `swift test --package-path app/Atelier` -> tests pass, including new tests for context block building.
- Manual: open a file tab, run explain quick action -> streamed answer mentions the file path.
- Manual: stop Ollama, send a prompt -> panel shows connection error, app stays responsive.
- Manual: resize window narrow and wide -> no crash, sidecar layout holds.
