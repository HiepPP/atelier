# Plan Context

## Shared Context

- Atelier is a macOS 26 SwiftUI app built with Swift 6.2 and SwiftTerm.
- Codex and Claude keep running as normal interactive TUI processes inside terminal tabs.
- [app/Atelier/Sources/Atelier/Agent/AgentResponses.swift](app/Atelier/Sources/Atelier/Agent/AgentResponses.swift) already parses final answers from Codex and Claude JSONL transcripts.
- [app/Atelier/Sources/Atelier/Agent/AgentResponsesView.swift](app/Atelier/Sources/Atelier/Agent/AgentResponsesView.swift) currently shows responses as a separate center tab.
- [app/Atelier/Sources/Atelier/Agent/AgentMarkdownView.swift](app/Atelier/Sources/Atelier/Agent/AgentMarkdownView.swift) already renders basic Markdown blocks and Mermaid cards.
- [app/Atelier/Sources/Atelier/Terminal/MermaidPreview.swift](app/Atelier/Sources/Atelier/Terminal/MermaidPreview.swift) renders Mermaid through bundled local resources.
- [app/Atelier/Sources/Atelier/Workspace/Views/ContentView.swift](app/Atelier/Sources/Atelier/Workspace/Views/ContentView.swift) owns the workspace columns and command bar.
- [app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift](app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift) owns terminal, file, and agent center tabs.

## Product Contract

- SwiftTerm remains the authoritative input and interaction surface.
- The panel reads transcript files only. It never sends prompts or commands.
- The panel never writes transcript files or changes SwiftTerm buffer state.
- Opening or resizing the panel must not recreate a terminal process or terminal view.
- Provider and session ID form the session identity. Equal IDs from different providers stay separate.
- The panel shows complete final answers. It does not mirror partial reasoning or command output.
- Transcript parse failures remain local to one file. Other sessions continue updating.
- Prompt text, response text, file content, and credentials are never logged.

## Layout Contract

- Wide windows show a resizable trailing preview beside the current center content.
- Narrow windows show a dismissible trailing overlay. The terminal stays mounted behind it.
- The command bar toggle shows unread state and opens the latest active session.
- The panel offers all sessions and stable per-session selection.
- Closing the panel returns focus to the previous terminal when possible.
- Cards use Atelier's warm neutral palette, quiet borders, and compact typography.

## Mermaid Contract

- Mermaid rendering uses bundled local HTML and JavaScript only.
- Diagram width follows the panel width through bounded width buckets.
- Resize keeps the previous image visible until a replacement is ready.
- A render failure opens selectable source automatically.
- Source remains available on successful diagrams through a clear toggle.

## Decisions

- Do not add Codex app-server or Claude print-mode runtimes.
- Do not add a second writer for any Codex or Claude session.
- Replace the Responses center tab with the preview panel.
- Keep reusable transcript, Markdown, and Mermaid code outside `TerminalController`.
- Use 1000 x 700 as the narrow UI check and 1600 x 1000 as the wide check.

## Open Decisions

- None.

## References

- [app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift](app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift)
- [app/Atelier/Sources/Atelier/Workspace/State/WorkspaceSession.swift](app/Atelier/Sources/Atelier/Workspace/State/WorkspaceSession.swift)
- [app/Atelier/Sources/Atelier/Terminal/TerminalController.swift](app/Atelier/Sources/Atelier/Terminal/TerminalController.swift)
- `swift test --package-path app/Atelier --filter AgentResponsesTests`
