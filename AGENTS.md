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

This project is indexed by GitNexus as **atelier** (6804 symbols, 42878 relationships, 300 execution flows). Use the GitNexus MCP tools to understand code, assess impact, and navigate safely.

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
