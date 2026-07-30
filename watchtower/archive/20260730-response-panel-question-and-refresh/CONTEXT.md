# Context

## Scope

Both TASKs change the agent response overlay: the panel that `Cmd-R` opens on the trailing side of
the center work surface.

## Owning Files

- [app/Atelier/Sources/Atelier/Agent/AgentResponses.swift](app/Atelier/Sources/Atelier/Agent/AgentResponses.swift):
  holds `AgentResponse`, `AgentTranscriptParser`, the `AgentTranscriptMonitor` actor, the
  `TranscriptDirectoryWatcher`, and the `AgentResponsesModel` observable.
- [app/Atelier/Sources/Atelier/Agent/AgentResponsesView.swift](app/Atelier/Sources/Atelier/Agent/AgentResponsesView.swift):
  holds the panel view, its header, its single response card, and its footer.
- [app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift](app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift):
  mounts the panel as `AgentResponseOverlay`. Neither TASK needs to change it.
- [app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift](app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift):
  holds every parser, monitor, and model test. Add new tests here.
- [DESIGN.md](DESIGN.md): the `### Agent Responses` section is the design contract. Update it before
  changing behavior.

## How the Panel Gets Data

1. `AgentResponsesModel.start` runs one restore, then starts `TranscriptDirectoryWatcher`.
2. A filesystem event schedules a debounced refresh and a longer trailing refresh.
3. A refresh calls `AgentTranscriptMonitor.loadResponses`, which walks transcript roots, skips
   unchanged files by fingerprint, parses only new bytes, and returns the newest 100 responses.
4. The model keeps only responses it has not seen, sorts them by timestamp, and caps the list at 300.

## Rules That Apply

- Keep UI state on `MainActor`. Keep parsing and file reads inside the `AgentTranscriptMonitor` actor.
- Do not remove the existing performance guards: the fingerprint skip, the discovery walk cache, the
  newest-first stop, the head probe, and the 1 MiB first-parse cap. See the 2026-07-28 entries in
  [watchtower/MEMORY.md](watchtower/MEMORY.md).
- Every clickable control needs `.atelierPointerCursor()`.
- Never mutate observable state from a layout-derived value. Defer such work with
  `Task { @MainActor in ... }`.
- Never log prompt text, question text, or response text.
- Invoke `$swiftui-expert-skill` before writing or editing Swift code in this repo.
