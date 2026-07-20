# TASK-004 Terminal quick actions - Outcome

## Status

DONE

## Changed

- `app/Atelier/Sources/Atelier/Agent/Sidecar/SidecarTerminalActions.swift`
  - Implemented `quickActions(for:)`: returns two actions only when
    `context.kind == .terminal`, otherwise `[]`.
  - Added `static let terminalActions: [SidecarQuickAction]` in an extension:
    - `terminal.explainError` ("Explain Last Error",
      `exclamationmark.triangle`) - one-shot prompt telling Gemma to call
      `read_terminal_output` and diagnose the most recent error and its fix.
    - `terminal.explainCommand` ("Explain Last Command", `terminal`) - one-shot
      prompt telling Gemma to call `read_terminal_output` and explain the last
      command and its result.

No shared files touched. Only this feature file and this outcome sidecar changed.

## Contract

- Signature matches the real stub: `func quickActions(for context:
  GemmaSidecarTabContext?) -> [SidecarQuickAction]` on the `@MainActor
  @Observable final class SidecarTerminalActionsModel`.
- `GemmaSidecarModel.allQuickActions(for:)` already appends
  `terminalActions.quickActions(for: context)`, so both actions surface in the
  quick-actions row for a terminal tab. Buttons send `action.prompt` via
  `services.runInteractive`, which streams into the interactive response area.
- Prompts are pure user prompts. They add no context prefix; the interactive
  model's `contextProvider` prepends the tab context block via
  `GemmaSidecarContextComposer`.
- Actions are one-shot and read-only: they only ask Gemma to call the existing
  read-only `read_terminal_output` tool. No file writes, shell, or git.

## Verified (by reasoning; integrate stage compiles)

- Working directory requirement: `TerminalTabsModel.selectedSidecarContext`
  sets `workingDirectory: workspacePath` for the `.terminal` case
  (TerminalTabs.swift:170), and `GemmaSidecarContextComposer.contextBlock`
  emits `Working directory: ...` (SidecarServices.swift:79-81). So the injected
  context includes the terminal working directory with no change needed here.
- Terminal tab shows both actions: `context.kind == .terminal` is the only
  branch returning a non-empty array; `.file`, `.gitDiff`, `.gemma`, and `nil`
  return `[]`.
- Explain-error flow: the button sends the prompt to `runInteractive`; the
  interactive runtime exposes the `read_terminal_output` tool
  (WorkspaceToolModels.swift:133) routed by WorkspaceToolExecutor
  (WorkspaceToolExecutor.swift:61) using the MainActor scrollback snapshot, so a
  failing command's real output is read and a diagnosis streams into the
  response area. Tool activity renders via the existing `GemmaToolActivity`
  display in `GemmaSidecarView.activityView` - not rebuilt.
- Compilation: `SidecarQuickAction(id:title:systemImage:prompt:)` matches the
  real init; multiline string literals use valid backslash line-continuation;
  the `static let [SidecarQuickAction]` extension pattern mirrors the verified
  `GemmaSidecarModel.fileActions`/`gitDiffActions` constants; action ids
  (`terminal.explainError`, `terminal.explainCommand`) do not collide with
  existing built-in action ids.
- Build/test not run (shared `.build` race across concurrent feature builders),
  per task instructions.
