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

Use `rg` for repository search. Do not add or use GitNexus metadata in this repository.

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

Add deterministic non-UI coverage under `Tests/AtelierTests`. Keep `SelfTest.swift` for packaged binary checks. Every change must pass build, tests, and self-test. UI changes also require native checks at narrow and wide window sizes. Record exact failures and screenshots when relevant.

### Test Scope and UI Automation

- Keep verification proportional to the change and its runtime risk. Start with targeted deterministic checks, then run the required full gates once.
- Define the exact UI states and evidence needed before starting automation. Stop when those acceptance points are covered.
- For native terminal, editor, web, or Metal surfaces, define a visible content sentinel before testing. The sentinel must remain visible after every transition; a selected tab, live process, or blank surface is not proof of success.
- Confirm the target app, process, and window before every automated UI input. If another app becomes active, stop immediately and return to the target without interacting with the other app.
- Use one controlled capture path for visual proof. After one capture method fails, switch methods once or report the limitation instead of retrying indefinitely.
- Timebox UI automation. Run each acceptance path once by default, stop when evidence is sufficient, and repeat only for intermittent behavior or a failed pass.
- Do not repeat builds, tests, self-tests, or launch scripts unless code changed or the prior result was incomplete.
- Separate product failures from automation, environment, window-focus, and capture failures in the final report.
- Prefer read-only system checks. Change accessibility or system settings only when required, then restore the original value.

## Commit & Pull Request Guidelines

Use concise Conventional Commit messages, such as `fix(ui): align split-view dividers`. Keep commits scoped to one outcome.

Pull requests should include a short problem statement, implementation summary, verification commands, and before/after screenshots for visual changes. Never include `.build`, `dist`, temporary workspaces, credentials, or signing identities.
