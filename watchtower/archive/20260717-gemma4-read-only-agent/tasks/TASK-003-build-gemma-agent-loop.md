# TASK-003 Build the Gemma Agent Loop

Group: C (agent lifecycle shared with the native tab)

## Brief

Goal: Join Ollama streaming and workspace tools into one owned, cancellable Gemma session.

Change: Separate transport and tools -> one read-only multi-turn agent loop with observable presentation state.

How:

- Add a `@MainActor` observable model for messages, status, active tool, errors, and user intents.
- Add an actor that sends the prompt, handles tool calls, executes allowed tools, and sends results back.
- Preserve complete assistant tool-call messages and tool results in the Ollama conversation history.
- Reject unknown tools and invalid arguments before dispatch.
- Cap tool iterations, transcript growth, and retained tool output.
- Ensure a new prompt, stop action, tab close, or workspace close cancels owned work.
- Add an `Agent` unified logging category without logging content.
- Use narrow test substitution only where deterministic loop tests require it.

Files:

- [app/Atelier/Sources/Atelier/Agent/GemmaAgentModel.swift](app/Atelier/Sources/Atelier/Agent/GemmaAgentModel.swift) (own UI-facing session state and intents)
- [app/Atelier/Sources/Atelier/Agent/GemmaAgentRuntime.swift](app/Atelier/Sources/Atelier/Agent/GemmaAgentRuntime.swift) (run the bounded multi-turn tool loop)
- [app/Atelier/Sources/Atelier/Shared/Logging/AppLogger.swift](app/Atelier/Sources/Atelier/Shared/Logging/AppLogger.swift) (add the Agent category)
- [app/Atelier/Tests/AtelierTests/GemmaAgentRuntimeTests.swift](app/Atelier/Tests/AtelierTests/GemmaAgentRuntimeTests.swift) (cover tool sequencing, limits, errors, replacement, and cancellation)

Expected result:

- One prompt can drive several safe tool calls and finish with a streamed answer.
- The UI model exposes predictable idle, running, failed, and cancelled states.
- Every stop or replacement path cancels network and tool work.

## Verify

- `swift test --package-path app/Atelier --filter GemmaAgentRuntimeTests` -> all loop and lifecycle tests pass.
- Run a scripted two-tool conversation -> tool calls execute in order and the final answer streams.
- Return repeated tool calls past the configured limit -> the run stops with a typed limit error.
- Cancel during transport and tool execution -> both paths finish without retained work.
