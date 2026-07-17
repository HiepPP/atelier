# Plan Context

## Shared Context

- Atelier targets macOS 26 with Swift 6.2 and strict concurrency.
- SwiftUI owns presentation state. Actors own network, file, search, and agent-loop work.
- The first Gemma slice is read-only. It must not edit files or run arbitrary shell commands.
- Ollama runs locally as the authenticated gateway to `gemma4:cloud`.
- Existing build, test, self-test, terminal, editor, file tree, and Git behavior must remain stable.

## Decisions

- Use `http://localhost:11434/api/chat` instead of storing an Ollama API key.
- Use `gemma4:cloud` as the first fixed model.
- Provide only `search_workspace`, `read_file`, and `read_git_diff` tools.
- Keep one Gemma session per workspace for this slice.
- Do not add a cross-provider agent protocol before a second provider exists.
- Do not rename the existing tab subsystem during this focused plan.

## Open Decisions

- None.

## References

- [app/Atelier/Package.swift](app/Atelier/Package.swift)
- [app/Atelier/Sources/Atelier/Workspace/State/WorkspaceSession.swift](app/Atelier/Sources/Atelier/Workspace/State/WorkspaceSession.swift)
- [app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift](app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift)
- [app/Atelier/Sources/Atelier/Git/GitService.swift](app/Atelier/Sources/Atelier/Git/GitService.swift)
- [app/Atelier/Tests/AtelierTests/AtelierTests.swift](app/Atelier/Tests/AtelierTests/AtelierTests.swift)
- [Ollama Cloud](https://docs.ollama.com/cloud)
- [Ollama tool calling](https://docs.ollama.com/capabilities/tool-calling)
- [Gemma 4 model](https://registry.ollama.com/library/gemma4)
