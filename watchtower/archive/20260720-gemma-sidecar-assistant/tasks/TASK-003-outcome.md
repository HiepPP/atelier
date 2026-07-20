# TASK-003 Outcome

## Status

DONE

## Changed

- `Agent/Tools/WorkspaceToolModels.swift`
  - Added `WorkspaceToolName.readTerminalOutput = "read_terminal_output"`.
  - Added `WorkspaceReadTerminalInput { lines: Int? }`.
  - Added `WorkspaceToolError.noTerminalSelected` with a clear message.
  - Added the tool's `OllamaToolDefinition` (optional integer `lines`).
- `Agent/Tools/WorkspaceToolExecutor.swift`
  - Injected `terminalSnapshot: (@MainActor @Sendable (Int) -> String?)?`.
  - Routed `read_terminal_output`: caps lines (default 200, max 400), awaits the
    MainActor snapshot provider, throws `noTerminalSelected` when the provider is
    absent or returns nil, and bounds output to 100k characters (marks `truncated`).
    Terminal content is never logged.
- `Agent/GemmaAgentRuntime.swift` - `activityDetail` now handles the new case (keeps
  the switch exhaustive; no content logged).
- `Terminal/TerminalController.swift`
  - Added `TerminalScrollbackPolicy` (default 200, max 400).
  - Added MainActor `scrollbackSnapshot(lines:)` reading the SwiftTerm buffer via
    `getTerminal().getText(...)`, trimming trailing blank rows and returning the last
    N lines as plain text.
  - Added `onCommandFinished: ((Int32) -> Void)?` plus an OSC 133 handler that parses
    the `D;<exit>` mark and fires it on the MainActor (never fires without marks).
- `Terminal/TerminalTabs.swift` - `selectedTerminalScrollback(lines:)` (nil unless the
  selected tab is a terminal) and command-finished handler installation used to feed
  the executor's snapshot provider.
- `Tests/AtelierTests/WorkspaceToolExecutorTests.swift` - added a terminal-output test
  plus a `TerminalSnapshotSpy`: default lines = 200, large request capped at 400,
  character cap truncates at 100k, and `noTerminalSelected` for both nil provider and
  nil snapshot.

## Contract

`read_terminal_output` is a read-only tool with an optional `lines` integer. The
scrollback snapshot runs on the MainActor (SwiftTerm buffer is MainActor); the actor
executor reaches it through an injected MainActor `@Sendable` provider. Lines are
capped (default 200, max 400) and characters bounded via the existing bounded-result
pattern. A clear `noTerminalSelected` error is returned when no terminal tab is
selected. No terminal content is logged.

## Verified

- `swift build --package-path app/Atelier` clean.
- `swift test --package-path app/Atelier` - 147 tests pass; the terminal-output test
  covers the line cap, character cap, and no-terminal error.
- `app/Atelier/.build/debug/Atelier --selftest` - ALL PASS.
- SwiftTerm API confirmed against `.build/checkouts/SwiftTerm`: `getTerminal()`,
  `getText(start:end:)`, `registerOscHandler(code:handler:)` are public; `Buffer` and
  `Position` are public.
