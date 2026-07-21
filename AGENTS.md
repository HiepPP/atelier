# Repository Guidelines

## Project Structure & Module Organization

Atelier is a macOS 26+ SwiftUI application built with Swift 6.2 and Swift Package Manager.

- `app/Atelier/Sources/Atelier/`: production Swift sources. Keep views, models, services, and AppKit bridges in focused files.
- `app/Atelier/Tests/AtelierTests/`: focused tests for models, parsers, persistence, and services.
- `app/Atelier/Packaging/`: application bundle metadata, including `Info.plist`.
- `app/Atelier/Resources/`: source assets used to build the application bundle.
- `app/Atelier/scripts/`: build, install, signing, logging, and verification scripts.
- `Vendor/Luminare/`: pinned local Luminare package and its required license.
- `README.md`: current product, architecture, and development reference.

Generated directories such as `.build/` and `dist/` must remain untracked.

## Required SwiftUI Skill

Before writing, editing, reviewing, or refactoring code in this repository, always invoke and follow `$swiftui-expert-skill` from `.agents/skills/swiftui-expert-skill/SKILL.md`.

## Design System Contract

Read `DESIGN.md` before changing code. Follow its current architecture, tokens, component contracts, interaction rules, accessibility rules, and verification requirements.

- Treat `DESIGN.md` as the design contract for the shipped application.
- If a new requirement changes the contract, update `DESIGN.md` before editing code.
- If `DESIGN.md` is stale or conflicts with the requested behavior, reconcile and update it first.
- Do not leave code and `DESIGN.md` describing different behavior after a change.
- When the design contract stays unchanged, keep `DESIGN.md` unchanged and follow it during implementation.

## Build, Test, and Development Commands

Run commands from the repository root:

```bash
swift build --package-path app/Atelier
swift test --package-path app/Atelier
app/Atelier/.build/debug/Atelier --selftest
app/Atelier/scripts/build_and_run.sh run
app/Atelier/scripts/build_and_run.sh --verify
app/Atelier/scripts/build_and_run.sh --release
```

`swift build` compiles the package. `swift test` runs focused core tests. `--selftest` checks persistence, file loading, Git parsing, and Git operations. The main script builds, signs, installs, and optionally verifies the app process. The release script creates `app/Atelier/dist/Atelier.app`.

## Post-Implementation Build

After completing any implementation task, automatically run `app/Atelier/scripts/build_and_run.sh` to build and launch the updated app.

- Run it once the code change is finished and `swift build`/`swift test` pass.
- Default to `app/Atelier/scripts/build_and_run.sh run` to build, sign, install, and open the app.
- If the build fails, report the failure and stop. Do not mark the task complete.
- Skip only when the change touches no Swift sources (docs, scripts, or metadata only).

## Coding Style & Naming Conventions

Use four-space indentation and standard Swift API naming. Types use `UpperCamelCase`; properties, methods, and enum cases use `lowerCamelCase`. Name SwiftUI views with a `View` suffix and observable models with a `Model` suffix. Prefer small extensions and native SwiftUI modifiers before adding abstractions. Keep AppKit customization defensive and idempotent.

Use `rg` for plain-text repository search: literal strings, symbol names, file globs, quick greps. Use GitNexus for code intelligence: impact analysis before edits, caller/callee context, execution-flow tracing, safe renames, and pre-commit change detection. Pick the tool by purpose; do not use GitNexus as a text grep, and do not use `rg` to reason about the call graph.

## Performance Rules

These rules come from shipped CPU/RAM regressions (100% CPU file-tree reload loop, per-draw color allocation). Follow them for every change.

### No Redundant Invalidation

- Never call `reloadData`/`reloadItem`/`needsDisplay` after a data refresh that produced no change. Diff first (identity or `Equatable`), reload only on real change. The file tree loop came from unconditional `reloadItem` after every directory load.
- Debounce filesystem- and watcher-driven refreshes (git status, directory reloads) with a trailing delay; a burst of FSEvents must collapse to one refresh and at most one subprocess spawn.
- Coalesce high-frequency `@Observable` mutations (streaming LLM deltas, progress ticks) into batched flushes (~80 ms). One mutation per token re-renders and re-parses the whole transcript.

### No Allocation in Draw/Layout/Per-Row Paths

- Never allocate `NSColor`, `NSFont`, `NSImage`, attribute dictionaries, or `NSBezierPath` inside `draw()`, `layout()`, cell `configure`, or dynamic color provider closures. Precompute or cache; invalidate the cache only when the input (scale, appearance, font) changes.
- `NSColor(name:)` provider closures run on every draw-time resolution: capture precomputed colors, never build them inside the closure.
- Per-keystroke search/rank paths must not lowercase, `Array(...)`-convert, or build dictionaries per candidate; precompute at index time.

### Bounded Work and Memory

- Iterate visible rows (`rows(in: visibleRect)`), never `0..<numberOfRows`, for refresh loops.
- Every append-only collection held by a long-lived model needs a cap (messages, responses, activities, caches).
- Watch the narrowest filesystem scope possible and filter event paths (`IgnoreRules`, `.git` internals) before reacting.

### Verify

- After any perf-relevant change, launch via `app/Atelier/scripts/build_and_run.sh run` and confirm idle CPU stays in the 0.2-2% range (`ps -p PID -o %cpu=`). Sustained CPU with no interaction means an invalidation loop; profile with `sample PID 3` and check for repeating reload/draw frames before shipping.

## SwiftUI and AppKit Crash Rules

These rules come from a shipped crash: zooming the window crossed a width breakpoint mid-resize, `.onChange` mutated panel `@State` during AppKit's layout pass, and macOS trapped in `-[NSWindow _postWindowNeedsUpdateConstraints]`. `swift build` and `swift test` cannot catch this class of runtime Cocoa exception. Follow these rules to prevent it.

### Layout Reentrancy

- Never mutate `@State`, `@Observable`, or model state synchronously from a layout-derived value (`GeometryReader` size, `.onChange` of a size, `onGeometryChange`). Defer the mutation with `Task { @MainActor in ... }` so it runs on the next runloop, off the current layout pass.
- Do not add or remove structural views such as `HSplitView` children in response to a width breakpoint. Keep panes mounted and toggle visibility with `frame`, `opacity`, or `ViewThatFits`.
- Keep all UI mutation on `MainActor`. Keep Swift 6 strict concurrency and `defaultIsolation(MainActor)` enabled.

### Persistent AppKit Tab Content

- Never switch a long-lived `NSViewRepresentable` terminal, editor, web view, or Metal-backed surface in and out of the hierarchy when tab selection or adjacent panel visibility changes. Keep it mounted with stable identity and toggle allocated width, opacity, hit testing, and accessibility visibility.
- Never collapse an `HSplitView` child to exactly zero or leave it structurally empty. Keep a positive placeholder width or use native split-item collapse, then verify every pane still renders.
- A panel defined as an overlay must stay outside `HSplitView` and must not change the proposed size of its native content surface at any window width.
- An inactive native tab must release first responder. Pass explicit active state through the representable and controller, then restore focus only after the active view is attached.
- For a native tab-switch fix, run `native tab -> image or SwiftUI tab -> native tab` once at each relevant zoom and sidecar state. Repeat only when the bug is intermittent or the first pass fails.

### No Runtime Traps in UI

- Ban `!` force unwrap, `try!`, `as!`, unchecked subscript, `fatalError`, and `precondition` on any view or controller path. These raise `EXC_BREAKPOINT`. Use `guard let`, `if let`, and safe access instead.
- Keep AppKit customization defensive and idempotent, matching existing patterns.

### Verify and Test Against the Real Trigger

- A crash fix is not done until you drive the exact trigger (for example window zoom at a narrow and a wide size) and confirm no crash and no new report in `~/Library/Logs/DiagnosticReports/`.
- When investigating a crash, read the full `.ips` report, including `asiBacktraces`, not only the exception summary.
- Pure breakpoint policy needs a matching UI smoke that drives resize and zoom across each breakpoint. Unit tests on the policy alone do not cover the layout-pass wiring.

## Reading Atelier Runtime Evidence

This is a runtime-reading guide, not an implementation-reading guide. Start with live evidence. Do not open diagnostics source or query GitNexus until the runtime evidence identifies a useful clue.

### Runtime Mental Model

Read the snapshot as six independent layers. One layer supplies context for the next layer.

| Layer | Question it answers | Primary fields |
|-------|---------------------|----------------|
| Process | Is the whole process busy or growing? | PID, uptime, CPU delta, CPU time, physical footprint |
| Main thread | Can AppKit still service work? | Last heartbeat, heartbeat age, pending heartbeat |
| Workspace | What user state was active? | Workspace name, selected tab, tab counts, loaded file bytes |
| Editor | What was the selected editor doing? | Controller identity, geometry, scroll windows, height changes, highlight state |
| Diagnostics | Can this evidence be trusted? | Snapshot age, event count, dropped events, flush duration, write error |
| Verdicts | Which hypothesis deserves the next check? | Code, severity, confidence, summary, raw evidence |

Never skip directly to verdicts. A verdict is a heuristic pointer. The raw fields and capture artifacts remain the evidence.

### Collection Order

Use terminal commands from the repository root. Keep this pass read-only.

```bash
app/Atelier/scripts/atelier-doctor status --json
app/Atelier/scripts/atelier-doctor status --json
app/Atelier/scripts/atelier-doctor status --json
app/Atelier/scripts/atelier-doctor watch --interval 1
app/Atelier/scripts/atelier-doctor probe main
app/Atelier/scripts/atelier-doctor probe editor
app/Atelier/scripts/atelier-doctor probe editor-scroll --delta 400 --restore
app/Atelier/scripts/atelier-doctor capture --seconds 3
```

- Record the exact trigger time before reproducing the issue.
- Collect three status snapshots across at least two snapshot intervals.
- Use `watch` when the symptom develops over time. Stop it cleanly with Ctrl+C.
- Run `capture` immediately after the symptom. Do not change tabs or window state first.
- Run editor probes only when a text editor is selected.
- If the CLI cannot respond, use `pgrep -x Atelier`, then external `sample` on that PID.

### Read the Status Envelope First

Read fields outside `snapshot` before reading internal metrics.

| Field | Healthy reading | Suspicious reading | Meaning |
|-------|-----------------|--------------------|---------|
| `status` | `healthy` | `stale`, `degraded`, or `stopped` | Whether the CLI found a running app and usable snapshot |
| `pid` | Matches the active Atelier process | Missing or changes unexpectedly | Which process every later artifact must match |
| `schemaVersion` | `1` | Missing or unsupported | Whether this guide can interpret the JSON contract |
| `snapshotAgeSeconds` | Below the stale threshold | Increasing across reads | Whether the writer is still publishing evidence |
| `snapshotPath` | Bundle cache Runtime path | Unexpected location | Which generated file the CLI read |

Stop normal interpretation when status is `degraded`. Report the degraded reason first. A malformed or missing snapshot cannot prove application health.

### Read Snapshot Time Before Values

- Compare `generatedAt` across three reads. It should advance about once per second.
- Compare `monotonicTimeSeconds` for duration and event correlation.
- Use `generatedAt` for wall-clock matching with logs and reports.
- Use monotonic time for heartbeat age, event order, probe duration, and staleness.
- If values repeat because `generatedAt` did not advance, they are one observation, not three samples.

### Read Process and Main Thread Together

| Signal | How to read it | What it can support |
|--------|----------------|---------------------|
| `cpuPercent` | Compare several fresh snapshots and `ps`. Look for sustained values | Process-level load, never root cause alone |
| `cpuTimeSeconds` | Confirm it keeps rising while CPU remains high | Real CPU consumption instead of one noisy percentage |
| `physicalFootprintBytes` | Compare trend before and after the trigger | Memory pressure or retention suspicion |
| `heartbeatAgeMs` | Compare with the 250-500 ms cadence | Main-thread responsiveness |
| `pendingHeartbeat` | Read with age, never alone | `true` is normal while one ping is in flight |
| `lastHeartbeatAt` | Compare across fresh snapshots | Whether the main actor still acknowledges work |

Use these combinations:

| Heartbeat | CPU | Initial classification |
|-----------|-----|------------------------|
| Healthy | Low | Normal idle or non-CPU issue |
| Healthy | Sustained high | Background CPU loop or main work between acknowledgements |
| Stale above 1,000 ms | Sustained high | Main-thread CPU-bound suspected |
| Stale above 1,000 ms | Low | Main-thread blocked or waiting suspected |

Do not call low CPU healthy when the heartbeat is stale. Do not call high CPU a loop without a repeating sample stack.

### Read Workspace Context Before Editor Metrics

- `active` tells whether a workspace exists.
- `relativeRootName` identifies the workspace without exposing an absolute path.
- `selectedTabKind` decides which editor fields are applicable.
- Tab counts explain the expected number of retained sessions and controllers.
- `loadedFileBytes` is total retained file content, not proof of a leak.
- `fileSessionCount` should be read with file-tab counts and close events.
- `fileTabs` gives per-file byte count, load state, and preview state without content.

If `selectedTabKind` is `terminal`, an unattached editor and zero editor geometry are expected. Do not diagnose an editor failure from those zeros.

### Read Editor Metrics as One Geometry State

| Field group | How to read it | Suspicious pattern |
|-------------|----------------|--------------------|
| Controller | Compare selected ID, live count, and expected count | Live remains above expected after the grace window |
| Content | Compare bytes and line count only when content changes | Bytes remain after the owning file session closes |
| Viewport | Read origin, viewport height, document height, and maximum scroll together | Impossible range, changing document height, or origin outside range |
| Scroll window | Read inputs, bounds changes, and eligible no-movement inputs together | Several eligible inputs with no bounds movement away from edges |
| Height window | Read height-change count with recent content, font, wrap, or resize activity | Three or more unexplained changes in one window |
| Highlight | Read state, duration, and cancellation count as a sequence | Long running state or repeated cancellation without completion |
| Text apply | Compare duration only when a `textApplied` event occurred | Repeated long applies that align with the symptom |

`canScrollVertically` and `maximumScrollY` must both show remaining range. A no-movement input at the top or bottom edge is not an anomaly.

### Read Diagnostics Health Before Trusting Absence

- `eventCount` shows how much recent context is available.
- `droppedEventCount` means older recorder events were evicted by the hard cap.
- `lastFlushDurationMs` shows writer cost. Read its trend, not one flush.
- `lastWriteError` must be `null` for a healthy writer.
- An empty verdict list only means no current heuristic crossed its threshold.
- Stale snapshots cannot prove that counters stayed zero.

### Read Probe Results

| Probe | `ok` means | `notApplicable` means | `timeout` means |
|-------|------------|-----------------------|-----------------|
| `main` | Main actor acknowledged and returned latency | Not normally expected | Main actor did not answer before the mailbox timeout |
| `editor` | Fresh selected-editor snapshot was read without forcing layout | No selected text editor or no mounted editor | Main actor could not return editor state |
| `editor-scroll` | Origin moved toward the clamped target and cleanup ran | No editor, no scroll range, or request already at an edge | Probe could not finish before timeout |

For `editor-scroll`, compare `originBeforeY`, `originAfterY`, `movementY`, `maximumScrollY`, elapsed time, and `restored`. Positive movement with `restored: true` supports that the reversible probe and cleanup path completed.

### Read Capture Artifacts in Order

| Order | Artifact | Read | Extract |
|------:|----------|------|---------|
| 1 | `manifest.json` | Collector status, exit code, PID, timestamp | Which artifacts are trustworthy and which are degraded |
| 2 | `snapshot.json` | Same field order as live status | Frozen runtime state near capture time |
| 3 | `flight-recorder.json` | Monotonic event order and correlation IDs | What changed immediately before and during the symptom |
| 4 | `sample.txt` | Main thread, busy threads, repeated stacks, stack summary | Where CPU time or waiting accumulated |
| 5 | `log.txt` | Faults, errors, RuntimeDiagnostics category, signpost timing | Failed operations and interval boundaries |
| 6 | `vmmap-summary.txt` | Physical footprint and largest memory regions | Which memory class dominates the process |
| 7 | `diagnostic-reports.json` | Report timestamps and paths | Whether the reproduction created a new crash or hang report |

One degraded collector does not invalidate successful collectors. Qualify only the conclusion that depended on the missing evidence.

### Read the Flight Recorder as a Timeline

1. Start from the recorded trigger time.
2. Select the final 5-10 seconds around that time.
3. Sort by `monotonicTimeSeconds`, not JSON position assumptions.
4. Group by `correlationID` for one controller, tab, session, or probe.
5. Read lifecycle pairs and missing counterparts.
6. Compare event durations with snapshot counters and sample stacks.

Important sequences:

```text
loadStarted -> loadCompleted | loadCancelled
nativeEditorInitialized -> nativeEditorMounted -> nativeEditorAttached
nativeEditorDetached -> nativeEditorStopped -> nativeEditorDeinitialized
highlightStarted -> highlightCompleted | highlightCancelled | highlightFailed
wordWrapLayoutChanged | fontLayoutChanged -> grace window -> stable height
editor-scroll probe -> movement result -> restore
```

A missing counterpart is a clue, not proof. The capture window may begin after the matching start event or end before cleanup.

### Read Sample Output

Read the sample in this order:

1. Confirm the sampled PID matches status and manifest.
2. Find `com.apple.main-thread` and inspect its dominant repeated stack.
3. Inspect other threads with repeated compute frames.
4. Read `Sort by top of stack` for dominant leaf frames.
5. Count recurrence across samples. Ignore one-off frames.
6. Match hot frames to the flight-recorder time window and symptom class.

```bash
rg -n "Call graph:|com.apple.main-thread|RuntimeDiagnostics|TextKit|layout|wait|lock|Total number in stack|Sort by top of stack" <capture>/sample.txt
```

| Sample pattern | Runtime interpretation |
|----------------|------------------------|
| Repeating main-thread compute frames, stale heartbeat, high CPU | Main-thread CPU-bound clue |
| Main thread parked in wait or lock, stale heartbeat, low CPU | Main-thread blocking clue |
| Repeating background compute frames, healthy heartbeat, high CPU | Background loop clue |
| Repeating layout or TextKit frames plus height churn | Layout churn clue |
| Diagnostics queue dominates samples or flush duration grows | Diagnostics overhead clue |

The hottest frame is not automatically the cause. Prefer the first app-owned frame that repeats and explains the broken runtime state.

### Read Memory Evidence

- Use `physicalFootprintBytes` and `vmmap-summary.txt`. Do not substitute RSS.
- Compare footprint before the trigger, during growth, and after closing the suspected tabs.
- Compare loaded file bytes, file-session count, file-tab count, and controller counts at the same times.
- A falling loaded-byte count with a rising footprint points away from file-content retention.
- A stable loaded-byte count with growing controllers points toward lifecycle retention.
- A large stable footprint is not a leak. A repeatable upward trend without release is the clue.

### Cross-Check Verdicts

| Verdict | Required cross-check |
|---------|----------------------|
| `mainThreadCpuBoundSuspected` | Stale heartbeat, sustained CPU, repeating main compute stack |
| `mainThreadBlockedSuspected` | Stale heartbeat, low CPU, wait or lock evidence |
| `scrollInputWithoutMovement` | Remaining scroll range, away from edge, editor-scroll probe |
| `documentHeightChurn` | Height timeline without content, font, wrap, or resize cause |
| `editorControllerLeakSuspected` | Lifecycle imbalance and live count above expected after grace |
| `physicalFootprintPressure` | Footprint trend and `vmmap` region evidence |
| `diagnosticsStale` | Live PID with non-advancing `generatedAt` |
| `diagnosticsWriterFailure` | Write error, flush-failure event, and filesystem or collector evidence |

Never restate a verdict as root cause. Report it as a hypothesis with supporting or conflicting evidence.

### Produce the Trace Clue

The runtime-reading result must narrow the next investigation to one thread, event sequence, state transition, or retained identity.

```text
Symptom:
Trigger time:
PID and workspace context:
Freshness and diagnostics health:
Heartbeat and CPU pattern:
Editor or retention pattern:
Recorder sequence and correlation ID:
Repeated sample stack:
Verdict cross-check:
Most useful trace clue:
Confidence:
Missing evidence:
Artifact path:
```

Only after this packet exists should the agent read implementation code or use GitNexus. Start GitNexus with the hot app-owned symbol, event name, or lifecycle transition found above. Do not start with a broad architecture query.

The handoff chain is:

```text
runtime symptom -> fresh state -> time-correlated events -> repeated stack -> one trace clue
```

## Testing Guidelines

Add deterministic non-UI coverage under `Tests/AtelierTests`. Keep `SelfTest.swift` for packaged binary checks. Every change must pass build, tests, and self-test. Run native UI checks with Atelier's window zoomed to full size by default. Do not test every window size. Record exact failures and screenshots when relevant.

### Test Scope and UI Automation

- Keep verification proportional to changed behavior and runtime risk. Prove non-visual behavior with CLI checks first.
- Define at most three acceptance points before launching the app. Each point needs a start state, one action, a visible sentinel, and the expected result.
- Run one shortest path at full window size. Add another size only when the request or bug explicitly depends on resize or a breakpoint.
- Launch the app once after deterministic checks pass. Do not repeat builds, tests, self-tests, or launch scripts without new code.
- Stop when acceptance evidence is complete. Repeat only after a failed pass or for a known intermittent bug.
- Separate product failures from automation, environment, focus, and capture failures in the final report.

### Computer Use Fast Path

- Use `$computer-use:computer-use` only for behavior that requires native UI interaction. Use shell commands for process, logs, CPU, crash reports, builds, and tests.
- Keep one persistent `node_repl` session. Initialize Computer Use once, then target Atelier directly with bundle identifier `app.atelier.Atelier`.
- Call `get_app_state` once before each acceptance path. Use the default accessibility-tree diff; request a full tree only when prior context is missing.
- Prefer accessibility text and `element_index` actions. Capture a screenshot only for visual evidence or when accessibility data is insufficient.
- Batch deterministic actions until the next decision point, then inspect state once. Do not inspect after every click, key, or text entry.
- Re-read state after UI changes and derive fresh element indexes. Never reuse an index from an older tree.
- Confirm app and window identity at path start and after any app switch. Do not re-confirm before every input while the same verified window stays active.
- Do not add manual sleeps. The runtime already waits after actions. If state looks stale, refresh once.
- On failure, retry once with fresh state. If direct targeting fails, call `list_apps` once and retry with its identifier. Then allow one screenshot-based coordinate action.
- For blank titlebar or custom chrome, refresh accessibility state and target an accessible title or control first. Coordinates are last resort.
- Default budget per acceptance path: five minutes, six state reads, one screenshot, and one retry per failed action. Report why before exceeding it.
- Keep final proof compact: tested path, visible sentinel, result, and console or crash status. Do not include raw accessibility trees or action transcripts.
- Prefer read-only system checks. Change accessibility or system settings only when required, then restore the original value.

## Commit & Pull Request Guidelines

Use concise Conventional Commit messages, such as `fix(ui): align split-view dividers`. Keep commits scoped to one outcome.

Pull requests should include a short problem statement, implementation summary, verification commands, and before/after screenshots for visual changes. Never include `.build`, `dist`, temporary workspaces, credentials, or signing identities.

<!-- gitnexus:start -->
# GitNexus — Code Intelligence

This project is indexed by GitNexus as **atelier** (7393 symbols, 47000 relationships, 300 execution flows). Use the GitNexus MCP tools to understand code, assess impact, and navigate safely.

> Index stale? Run `node .gitnexus/run.cjs analyze` from the project root — it auto-selects an available runner. No `.gitnexus/run.cjs` yet? `npx gitnexus analyze` (npm 11 crash → `npm i -g gitnexus`; #1939).

## Always Do

- **MUST run impact analysis before editing any symbol.** Before modifying a function, class, or method, run `impact({target: "symbolName", direction: "upstream"})` and report the blast radius (direct callers, affected processes, risk level) to the user.
- **MUST run `detect_changes()` before committing** to verify your changes only affect expected symbols and execution flows. For regression review, compare against the default branch: `detect_changes({scope: "compare", base_ref: "main"})`.
- **MUST warn the user** if impact analysis returns HIGH or CRITICAL risk before proceeding with edits.
- When exploring unfamiliar code, use `query({search_query: "concept"})` to find execution flows instead of grepping. It returns process-grouped results ranked by relevance.
- When you need full context on a specific symbol — callers, callees, which execution flows it participates in — use `context({name: "symbolName"})`.
- For security review, `explain({target: "fileOrSymbol"})` lists taint findings (source→sink flows; needs `analyze --pdg`).

## Never Do

- NEVER edit a function, class, or method without first running `impact` on it.
- NEVER ignore HIGH or CRITICAL risk warnings from impact analysis.
- NEVER rename symbols with find-and-replace — use `rename` which understands the call graph.
- NEVER commit changes without running `detect_changes()` to check affected scope.

## Resources

| Resource | Use for |
|----------|---------|
| `gitnexus://repo/atelier/context` | Codebase overview, check index freshness |
| `gitnexus://repo/atelier/clusters` | All functional areas |
| `gitnexus://repo/atelier/processes` | All execution flows |
| `gitnexus://repo/atelier/process/{name}` | Step-by-step execution trace |

## CLI

| Task | Read this skill file |
|------|---------------------|
| Understand architecture / "How does X work?" | `.claude/skills/gitnexus/gitnexus-exploring/SKILL.md` |
| Blast radius / "What breaks if I change X?" | `.claude/skills/gitnexus/gitnexus-impact-analysis/SKILL.md` |
| Trace bugs / "Why is X failing?" | `.claude/skills/gitnexus/gitnexus-debugging/SKILL.md` |
| Rename / extract / split / refactor | `.claude/skills/gitnexus/gitnexus-refactoring/SKILL.md` |
| Tools, resources, schema reference | `.claude/skills/gitnexus/gitnexus-guide/SKILL.md` |
| Index, status, clean, wiki CLI commands | `.claude/skills/gitnexus/gitnexus-cli/SKILL.md` |

<!-- gitnexus:end -->
