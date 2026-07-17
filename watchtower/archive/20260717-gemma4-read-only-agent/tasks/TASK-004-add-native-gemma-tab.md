# TASK-004 Add the Native Gemma Tab

Group: C (agent lifecycle shared with TASK-003)

## Brief

Goal: Add one native center tab for the read-only Gemma workspace assistant.

Change: Terminal and editor tabs only -> one additional Gemma tab with transcript, tool activity, input, and stop controls.

How:

- Add a SwiftUI view with a streamed transcript, compact tool rows, prompt input, errors, and stop control.
- Add a Gemma content case to the existing center tab subsystem without renaming that subsystem.
- Let the workspace open or select its single Gemma tab from one clear command-bar action.
- Make file references from agent results open the existing editor tab when practical.
- Give `WorkspaceSession` clear ownership of the Gemma session and stop it during workspace cleanup.
- Preserve terminal identity, editor identity, tab reorder, tab rename, word wrap, focus, and narrow layouts.
- Show actionable setup text when Ollama is unavailable or the user is not signed in.

Files:

- [app/Atelier/Sources/Atelier/Agent/GemmaAgentView.swift](app/Atelier/Sources/Atelier/Agent/GemmaAgentView.swift) (add the native agent interface)
- [app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift](app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift) (add Gemma tab content and cleanup)
- [app/Atelier/Sources/Atelier/Workspace/State/WorkspaceSession.swift](app/Atelier/Sources/Atelier/Workspace/State/WorkspaceSession.swift) (own and stop the Gemma session)
- [app/Atelier/Sources/Atelier/Workspace/Views/ContentView.swift](app/Atelier/Sources/Atelier/Workspace/Views/ContentView.swift) (add the Gemma tab entry action)
- [app/Atelier/Tests/AtelierTests/GemmaAgentModelTests.swift](app/Atelier/Tests/AtelierTests/GemmaAgentModelTests.swift) (cover one-session identity and workspace cleanup)

Expected result:

- The user can open one Gemma tab, send a prompt, inspect tool activity, and stop the run.
- Reopening Gemma selects the same workspace session instead of duplicating it.
- Closing the tab or workspace cancels active work without affecting terminals or editors.
- The existing workspace remains usable at narrow and wide window sizes.

## Verify

- `swift build --package-path app/Atelier` -> the application builds without concurrency warnings.
- `swift test --package-path app/Atelier` -> all existing and new tests pass.
- `app/Atelier/.build/debug/Atelier --selftest` -> all packaged checks pass.
- Open Gemma twice -> one tab exists and the second action selects it.
- Send a repository question -> streamed text and tool activity remain responsive.
- Stop a run, close the tab, and close the workspace -> no request or tool work remains.
- Check narrow and wide windows -> tab controls, transcript, composer, and Git view remain usable.
