# TASK-004 Terminal quick actions

Group: B (terminal intelligence ships as one slice)

## Brief

Goal: add sidecar quick actions for terminal tabs that use the new `read_terminal_output` tool.

Change: terminal tab shows generic prompt field only -> terminal tab shows explain-error and explain-command actions.

How:

- Add two quick actions for terminal tabs in the sidecar: explain the last error, explain what the last command did.
- Each action sends a one-shot prompt that tells Gemma to call `read_terminal_output` and analyze the recent lines.
- Include the terminal working directory in the injected context block.
- Show tool activity (tool name and detail) in the response area, reusing the existing `GemmaToolActivity` display.

Files:

- [app/Atelier/Sources/Atelier/Agent/](app/Atelier/Sources/Atelier/Agent/) (sidecar model quick-action definitions)
- [app/Atelier/Sources/Atelier/Workspace/Views/ContentView.swift](app/Atelier/Sources/Atelier/Workspace/Views/ContentView.swift) (sidecar action row for terminal tabs)

Expected result:

- A terminal tab shows both terminal quick actions in the sidecar.
- Running the explain-error action after a failing command streams a diagnosis based on real output.

## Verify

- `swift build --package-path app/Atelier` -> builds clean.
- Manual: run a failing command (for example `swift buld`), press explain-error -> answer quotes or reflects the real error text.
- Manual: press explain-command after `git status` -> answer describes the command output.
