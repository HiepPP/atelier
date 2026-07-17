# TASK-002 Build the Adaptive Preview Panel

Group: B (native response panel vertical slice)

## Brief

Goal: Show native responses beside the active TUI without replacing it. Adapt the same panel to narrow and wide workspace windows.

Change: Separate Responses center tab -> workspace preview panel beside the live TUI.

How:

- Remove the Responses content case from center tabs and its workspace open path.
- Add one workspace-owned panel presentation state and command bar toggle.
- Show a resizable trailing panel in wide windows.
- Show a dismissible trailing overlay in narrow windows.
- Keep the selected terminal view mounted when panel presentation changes.
- Restore the previous terminal focus after the panel closes when possible.
- Add a compact session picker with provider, short session ID, time, and unread state.
- Keep selection stable while new sessions and responses arrive.
- Mark only visible response content as read.
- Provide clear empty, waiting, and no-selection states.
- Add accessibility labels for the toggle, close action, session picker, and unread state.

Files:

- [app/Atelier/Sources/Atelier/Agent/AgentResponsesView.swift](app/Atelier/Sources/Atelier/Agent/AgentResponsesView.swift) (adaptive panel shell, header, session picker, and timeline)
- [app/Atelier/Sources/Atelier/Workspace/Views/ContentView.swift](app/Atelier/Sources/Atelier/Workspace/Views/ContentView.swift) (panel placement, width adaptation, toggle, and focus handoff)
- [app/Atelier/Sources/Atelier/Workspace/State/WorkspaceSession.swift](app/Atelier/Sources/Atelier/Workspace/State/WorkspaceSession.swift) (remove center-tab response opening while preserving monitor ownership)
- [app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift](app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift) (remove the Responses center-tab case and keep terminal identity stable)
- [app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift](app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift) (session selection, unread, lifecycle, and tab regression tests)

Expected result:

- Wide windows show the terminal and preview at the same time.
- Narrow windows show an overlay without destroying or restarting the terminal.
- The former Responses center tab no longer exists.
- Multiple provider sessions remain selectable during live updates.
- Opening, closing, and resizing the panel does not change terminal buffer content.

Prompt:

```text
Build a native SwiftUI preview panel around the existing response model. Keep the live SwiftTerm view mounted and authoritative. Use a docked layout when space allows and a trailing overlay when space is narrow.
```

## Verify

- `swift test --package-path app/Atelier --filter AgentResponsesTests` -> panel model and terminal tab regression tests pass.
- `rg -n "case \.responses|openResponses|responsesTabCount" app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift app/Atelier/Sources/Atelier/Workspace/State/WorkspaceSession.swift` -> no former center-tab response path remains.
- Open and close the panel around a running Codex TUI -> the same process and terminal content remain active.
- Repeat with a Claude TUI -> the same process and terminal content remain active.
