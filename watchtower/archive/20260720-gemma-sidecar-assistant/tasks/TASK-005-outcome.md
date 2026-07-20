# TASK-005 Terminal Guardian - Outcome

## Status

DONE

## Changed

- `app/Atelier/Sources/Atelier/Agent/Sidecar/TerminalGuardianFeature.swift`
  - Implemented `TerminalGuardianModel.handleCommandFinished(exitCode:)`: on a
    non-zero exit it runs ONE bounded, read-only `services.runBackground(_:)`
    call built from `services.readTerminalOutput(200)` plus the exit code,
    asking for a short diagnosis and a single suggested fix command, then
    publishes a dismissible `TerminalGuardianCard`.
  - Added published state `card` and `isRunning` (both `private(set)`), an
    `@ObservationIgnored` in-flight `task`, `dismissCard()`, and a real
    `cleanup()` that cancels the task and clears state.
  - Added a persisted enable toggle: model reads `UserDefaults` for
    `TerminalGuardianModel.settingsKey` (absent = enabled); the view exposes it
    via `@AppStorage(TerminalGuardianModel.settingsKey)` defaulting to `true`.
  - Implemented `TerminalGuardianCardView`: renders nothing when idle
    (no card and not running); otherwise a top-of-sidecar danger-tinted card
    with a warning header, exit code, streamed markdown diagnosis or a
    "Diagnosing..." spinner, a dismiss button, and the enable toggle.
- `watchtower/tasks/TASK-005-outcome.md` (this file).

No shared files touched. No `swift build`/`swift test` run (shared .build race).

## Contract

- Signatures preserved: `TerminalGuardianModel(services:)`,
  `handleCommandFinished(exitCode: Int32)`, `cleanup()`, and
  `TerminalGuardianCardView(model:)` (the new `@AppStorage` has a default, so
  the memberwise `init(model:)` used by `GemmaSidecarView` is unchanged).
- Read-only: only reads terminal scrollback and calls `runBackground`; no file
  writes, no shell, no git actions, never sends Enter, never pastes.
- One bounded call: `readTerminalOutput(200)` caps input; prompt output is
  additionally suffix-capped to 8000 chars.
- Debounce: `guard task == nil` drops new triggers while one run is in flight
  (checked and assigned synchronously on MainActor, so no race).
- Skip when unreachable: guards on `services.isOllamaConfigured()` and swallows
  thrown transport/cancellation errors in the run's `catch` (no card on error).
- Toggle off => no automatic calls (`isGuardianEnabled` guard).
- Cancellable: `cleanup()` and `dismissCard()` cancel `task`; the run re-checks
  `Task.isCancelled` after each await before publishing a card.
- Concurrency: model is `@MainActor @Observable`; the unstructured `Task`
  inherits MainActor isolation so all UI-state mutation stays on MainActor and
  the background hop happens inside `services.runBackground`. No
  `@unchecked Sendable`, no force unwrap / try! / as! / fatalError / precondition.
- Privacy: scrollback content is never logged; only a content-free
  `AppLogger.agent.debug("Terminal guardian started a diagnosis")` line.

## Verified (by reasoning)

- Failing command (exit != 0, enabled, reachable): passes all guards ->
  `startDiagnosis` sets `isRunning`, reads 200 lines, runs one background call,
  publishes a card with the diagnosis -> `TerminalGuardianCardView` shows the
  card at the top of the sidecar within seconds.
- Succeeding command (exit == 0): first guard returns, no state change, no
  card, no background call.
- Toggle off: `isGuardianEnabled` is false -> returns before any call; the view
  keeps showing the current card (with its toggle) until dismissed so the user
  can toggle back on before dismissing.
- Ollama unreachable: either `isOllamaConfigured()` is false (skip) or
  `runBackground` throws `.connection` (caught, no card); no crash, no spinner
  left hanging because `defer` always resets `isRunning`/`task`.
- Second failure while one runs: `guard task == nil` drops it (single run).
- Cleanup / dismiss mid-run: `task.cancel()` + cleared state; when the run
  resumes, `Task.isCancelled` short-circuits before publishing.
- No focus theft / not modal: the card has no `.focused`, no autofocus, no
  sheet/alert; it is a plain inline card in the existing VStack slot.

## Notes / assumptions

- Enable toggle defaults to ON so the reviewer's "failing command -> card"
  path works on first run; model and view agree via the absent-key-defaults-to-
  true convention.
- `readTerminalOutput(200)` reads the SELECTED terminal per the shared services
  contract (the command-finished handler does not carry the originating
  terminal). Normal case: the failing terminal is the selected one.
- Once the shared reachability hint flips false after a connection error, the
  guardian stays paused until another background/interactive run flips it back
  to true (shared `SidecarReachability`, owned by foundation, not this file).

## Integration fixes (round 1)

Applied by the integration fixer; both review findings resolved in
`TerminalGuardianFeature.swift`.

- Toggle dead-end fixed: `TerminalGuardianCardView.body` now renders a persistent
  minimal `idleRow` (label + enable switch) when there is no card, so disabling
  the guardian is no longer a one-way trap. The card path is unchanged.
- Debounce bypass fixed: added `currentRunID`; `startDiagnosis` bumps it per run
  and the `Task`'s `defer` clears `task`/`isRunning` only when
  `currentRunID == runID`, so a stale cancelled run cannot wipe a newer run's
  handle. At most one diagnosis runs at a time.

Verified: `swift build`, `swift test` (161 tests), and `--selftest` all pass.
