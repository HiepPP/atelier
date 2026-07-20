# TASK-006 Claude Code briefing - Outcome

## Status

DONE

## Changed

- `app/Atelier/Sources/Atelier/Agent/Sidecar/ClaudeBriefingFeature.swift`
  - Added top-level `enum ClaudeBriefingPhase` (idle / generating / ready(String) / failed(String)).
  - `ClaudeBriefingModel` (@MainActor @Observable):
    - `activeTerminalContext`: returns the selected context only when `kind == .terminal`, else nil.
    - `quickActions(for:)`: returns one `briefQuickAction` ("Brief for Claude", `text.append`) when `kind == .terminal`, else `[]`.
    - `generate()`: guards single-flight and terminal context, then starts one background `Task` calling `runGenerate()`.
    - `runGenerate()`: gathers `services.diffStat()`, `services.changedFiles()`, `services.readTerminalOutput(80)`, builds ONE bounded instruction, and awaits `services.runBackground(_:)`; sets `.ready` / `.failed`.
    - `cancel()`, `copyBriefing()` (NSPasteboard), `pasteBriefing()` (`services.pasteIntoTerminal`, no Return), `isolated deinit` cancels the task.
    - Pure `nonisolated static` helpers: `briefingInstruction(...)`, `boundedTail(...)`, `errorText(...)`; static `briefQuickAction`.
  - `ClaudeBriefingView`: renders `EmptyView` unless a terminal tab is selected; otherwise a compact bordered section with idle / generating / ready / failed states. Ready state shows the generated prompt (monospaced, selectable, bounded height) with Copy and Paste-into-terminal buttons plus Regenerate.
- `watchtower/tasks/TASK-006-outcome.md` (this file).

No shared files touched.

## Contract

- Type/signature match the real stub: `@MainActor @Observable final class ClaudeBriefingModel` with `init(services: SidecarServices)` and `func quickActions(for context: GemmaSidecarTabContext?) -> [SidecarQuickAction]`; `struct ClaudeBriefingView { let model: ClaudeBriefingModel }`. GemmaSidecarModel/GemmaSidecarView need no change.
- Container wiring honored: `GemmaSidecarModel.allQuickActions(for:)` appends `briefing.quickActions(for:)`, so the "Brief for Claude" action appears in the quick-action row and (per the fixed container) streams a conversational briefing into the interactive response area via `runInteractive`. The container also renders `ClaudeBriefingView(model: model.briefing)` below the prompt bar.
- Design deviation (documented): the task says the Brief action's run should invoke `services.runBackground`, but the shared quick-action row routes every action through `runInteractive` and gives features no callback. Since a `SidecarQuickAction` is data-only, a quick action cannot drive `runBackground`. To deliver the required runBackground -> paste-ready-prompt -> Copy/Paste flow, the trigger ("Generate") lives inside `ClaudeBriefingView`; the quick action remains as the required conversational entry point. This follows the real foundation code over the CONTRACT, as instructed.
- Read-only and cancellable: the only side effects are pasteboard write (explicit Copy) and terminal paste (explicit Paste, never sends Return). No file writes, shell, or git. `generate()`/`cancel()`/`deinit` provide the cancellation path; the background call is serialized by the foundation `SidecarBackgroundRunner`.

## Verified (by reasoning; integrate stage compiles)

- Brief names real files + real diff: `runGenerate()` embeds `services.changedFiles()` (git status paths), `services.diffStat()` (git diff --stat), `context.filePath`/`workingDirectory`, and `services.readTerminalOutput(80)` directly into the instruction, so Gemma's generated prompt is grounded in the actual work state. Inputs are bounded (40 files, 4000 chars diff, 4000 chars terminal tail) to keep one bounded call.
- Paste inserts without executing: `pasteBriefing()` calls `services.pasteIntoTerminal(text)`, which wraps `terminalTabs.pasteIntoSelectedTerminal(text)` and never sends Enter; the note text ("press Return to send") confirms the text is inserted, not run.
- Ollama unreachable handled: `services.runBackground` rethrows transport errors; `runGenerate` maps `OllamaCloudError` to `.failed` with `errorDescription` + `recoverySuggestion` (connection -> "Could not connect to Ollama. Start Ollama, then try again."). The feature is user-triggered only (no auto-cadence), so there is no background loop to gate on `isOllamaConfigured()`; the explicit-press failure path surfaces the real error and lets the reachability hint refresh on the next successful run.
- Preemption safety: when another serialized background run cancels ours, `OllamaCloudError.cancelled`/`GemmaAgentRuntimeError.cancelled` reset to `.idle` (retry-able) instead of showing a hard error.
- Empty-when-idle honored for non-terminal tabs: `ClaudeBriefingView` returns `EmptyView` when `activeTerminalContext` is nil (file/gitDiff/gemma tabs), so the container layout is unchanged there; a terminal tab shows the compact section.
- Concurrency: model is `@MainActor`; all `services` closures are `@MainActor`, and the heavy work runs off-MainActor inside the foundation background actor. The `Task { [weak self] in await self?.runGenerate() }` pattern and `isolated deinit` mirror `GemmaAgentModel`/`GemmaSidecarModel`. No `@unchecked Sendable`, no force-unwrap, `try!`, `as!`, `fatalError`, or `precondition`.
- Compilation checks against real APIs: `SidecarServices` members (`diffStat`/`changedFiles`/`readTerminalOutput`/`runBackground`/`pasteIntoTerminal`/`currentContext`), `SidecarQuickAction(id:title:systemImage:prompt:)`, `GemmaSidecarTabContext` fields, `TerminalTabInspectorKind.terminal`, `OllamaCloudError`/`GemmaAgentRuntimeError` (Equatable, `.cancelled`), theme tokens (`AtelierMetrics`, `AtelierTypography`, `AtelierTheme`, `AtelierGhostButtonStyle(tint:)`, `.atelierCard(fill:)`), and `AppLogger.agent.info(_:)` all match the read foundation sources. `Button(action:)` with a MainActor method reference mirrors the verified `Button(action: sendPrompt)` in GemmaSidecarView.
- No sensitive logging: the single log line is a fixed literal ("Gemma sidecar generated a Claude briefing"); prompts, diffs, terminal output, and generated text are never logged.
- Build/test/self-test not run (shared `.build` race across concurrent feature builders), per task instructions.

## Integration fixes (round 1)

Applied by the integration fixer to unblock the build.

- Swift 6 actor-isolation build error fixed: `maxTerminalTailCharacters`,
  `maxDiffStatCharacters`, and `maxChangedFiles` are now `nonisolated static let`
  so the `nonisolated static briefingInstruction` can read them off the main
  actor. Values and behavior unchanged. (This surfaced only after the
  SessionJournal error at the head of the build was cleared.)

Verified: `swift build`, `swift test` (161 tests), and `--selftest` all pass.
