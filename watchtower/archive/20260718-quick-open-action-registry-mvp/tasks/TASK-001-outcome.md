# TASK-001 Outcome

## Outcome

Status: DONE

Changed:
- Added a typed action catalog with stable metadata, availability rules, and live handlers.
- Routed global menu actions through the registry and added Command-T for a new terminal.
- Exposed selected-tab close availability without changing focus-local commands.

Contract:
- Menu commands read current AppModel and workspace state at dispatch time.
- Existing Open Folder, zoom, actual size, and focus shortcuts keep their behavior.
- Rename and word-wrap commands remain on their FocusedValues path.

Verified:
- `swift test --package-path app/Atelier --filter AtelierActionRegistryTests` -> 4 tests passed.
- `swift build --package-path app/Atelier` -> build completed successfully.
- Source check -> menu shortcuts and disabled states use the registry context.
