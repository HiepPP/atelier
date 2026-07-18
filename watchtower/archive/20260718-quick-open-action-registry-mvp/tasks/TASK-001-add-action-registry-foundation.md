# TASK-001 Add the Action Registry Foundation

Group: A (typed command foundation)

## Brief

Goal: Define one typed action catalog for menu commands and the future command palette. Keep action metadata and execution in one tested path.

Change: Scattered command metadata -> typed action IDs, descriptors, availability, and dispatch.

How:

- Add stable action IDs, titles, categories, symbols, and shortcut labels.
- Add one MainActor dispatcher that reads current AppModel and workspace state.
- Cover Open Folder, Close Workspace, New Terminal, Close Tab, Open Gemma, zoom controls, and focus mode.
- Keep focus-local tab rename and word-wrap actions on their existing FocusedValues path.
- Refactor overlapping AppCommands buttons to use registry metadata and dispatch.
- Preserve current shortcuts and disabled states.
- Add deterministic tests for catalog order, unique IDs, availability, and dispatch routing.

Files:

- [app/Atelier/Sources/Atelier/Commands/AtelierActionRegistry.swift](app/Atelier/Sources/Atelier/Commands/AtelierActionRegistry.swift) (new action IDs, descriptors, context rules, and dispatcher)
- [app/Atelier/Sources/Atelier/App/AppCommands.swift](app/Atelier/Sources/Atelier/App/AppCommands.swift) (route supported menu commands through the registry)
- [app/Atelier/Sources/Atelier/App/AppModel.swift](app/Atelier/Sources/Atelier/App/AppModel.swift) (expose narrow action entry points when the registry needs them)
- [app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift](app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift) (expose stable tab availability needed by action context)
- [app/Atelier/Tests/AtelierTests/AtelierActionRegistryTests.swift](app/Atelier/Tests/AtelierTests/AtelierActionRegistryTests.swift) (catalog and availability tests)

Expected result:

- Every registry action has one stable ID and one display descriptor.
- AppCommands and the future palette share the same title and availability rules.
- Existing menu shortcuts still run the same behavior.
- No action captures stale workspace or tab state.

Prompt:

```text
Implement the typed Atelier action registry described in this TASK. Keep descriptors data-only where possible. Use current AppModel and WorkspaceSession state at dispatch time. Do not add configurable keymaps or move focus-local rename and word-wrap commands into the registry.
```

## Verify

- `swift test --package-path app/Atelier --filter AtelierActionRegistryTests` -> all registry tests pass.
- `swift build --package-path app/Atelier` -> the command refactor compiles under Swift 6.2 strict concurrency.
- Open Folder, Close Workspace, zoom, and focus mode menu items keep their current shortcuts and disabled states.
