# TASK-002 Outcome

## Outcome

Status: DONE

Changed:
- Added `app/Atelier/Sources/Atelier/Settings/AtelierAppearanceSettings.swift`. It holds
  `nonisolated enum AtelierAppearancePolicy` (range 0.8-1.6, step 0.05, default 1.0,
  `clampedTextScale`, `percentLabel`, and the six settings keys) and
  `@MainActor @Observable final class AtelierAppearanceModel` (`codeLigaturesEnabled`,
  `showsMenuBarExtra`, `private(set) var codeFontRevision`, injected `UserDefaults`).
- `AtelierZoomModel` now takes `defaults: UserDefaults = .standard`, stored with
  `@ObservationIgnored`. Every read and write in the class routes through it, including the sizing
  mode and the agent response text scale.
- Added `appTextScale`, `terminalTextScale`, and `editorTextScale` as `private(set)` properties,
  loaded and clamped at init, with `setAppTextScale(_:)`, `setTerminalTextScale(_:)`, and
  `setEditorTextScale(_:)`. Each setter clamps, returns early on no change, assigns, then writes
  its key.
- Derived scales now follow the contract: `chromeScale` and `sidebarScale` multiply by
  `appTextScale` under their existing caps, `contentScale` is `renderScale * appTextScale`, and the
  new `terminalScale` and `editorScale` use their own multipliers.
- Manual zoom persists under `atelier.manualZoomByDisplay.v1`. The map loads clamped at init and
  writes after the zoom settle task completes, after a display swap, and after
  `applyLayoutProfileState`. The settle task's cancellation path writes nothing.
- Review fix. `updateForCurrentDisplay()` now treats the first key resolution as a separate branch,
  guarded by the new `private var hasResolvedDisplayKey`. The first call adopts the resolved key,
  restores its stored zoom, and writes nothing. Every later real display swap keeps the old
  save-then-restore-then-persist path. The shared restore body moved into
  `restoreManualScale(forDisplayKey:)`. This removes two defects the persistence exposed: the seed
  key `"comfortable"` was written to disk on every launch, and a display whose `displayKey` equals
  that seed never restored its own stored zoom.
- Added `resetAppearance()`. It returns the three text scales to 1.0, then calls the existing
  `reset()` so the focus mode rules stay in one place.
- `AppModel` owns `let appearance: AtelierAppearanceModel`, built in the same init from
  `environment.layoutProfileDefaults ?? .standard`. The zoom model receives the same defaults, so
  today's production and test behavior is unchanged (`.live()` already passes `.standard`, and
  tests pass nil).
- The scene body passes `.environment(model.appearance)` beside `.environment(model.zoom)` on
  `applicationContent` and on the `Settings` scene.

Contract:
- One owner for scale math. `AtelierZoomModel` still derives every scale from `renderScale`.
- Zoom range 0.8 to 2.0 in 0.1 steps, chrome cap 1.2, sidebar cap 1.5, 200 ms settle delay, and the
  focus mode rules are all unchanged. `clampedZoomScale` is a private extraction of the clamp that
  `requestScale` and `applyLayoutProfileState` already shared, with an `isFinite` guard added.
- `AtelierZoomModel(windowController:)` keeps its old call shape through the defaulted parameter,
  so `AtelierTests.swift:474` still compiles unchanged.
- New keys: `atelier.appTextScale`, `atelier.terminalTextScale`, `atelier.editorTextScale`,
  `atelier.manualZoomByDisplay.v1`, `atelier.codeLigaturesEnabled`, `atelier.showsMenuBarExtra`.

Verified:
- GitNexus `impact({target: "AtelierZoomModel", direction: "upstream"})` -> risk CRITICAL,
  190 impacted, 183 direct. Symbol-level dependents are `AtelierActionHandlers.live`,
  `AtelierActionHandlers.showSidebarTab`, `AtelierActionRegistry.context`, `AppCommands`,
  `WorkspaceView`, and `ContentView.paletteOverlay/presentPalette/activate`. The rest of the count
  is file-level IMPORTS noise. No public member was removed or renamed, so no dependent needed a
  change.
- `rg -n "terminalScale|editorScale|appTextScale" app/Atelier/Sources/Atelier/App/AtelierApp.swift`
  -> 10 hits covering the three text scales and both new derived values.
- `rg -n "UserDefaults.standard" app/Atelier/Sources/Atelier/App/AtelierApp.swift` -> exit 1, no
  match.
- `swift build --package-path app/Atelier` -> exit 0. GROUP-LEVEL RUN, shared with TASK-003.
- `swift test --package-path app/Atelier` -> exit 0, 471 tests in 46 suites passed, including
  `LayoutProfileTests` and `DisplaySizingTests`. GROUP-LEVEL RUN, shared with TASK-003. The first
  run of the session reported 1 issue whose text was cut off by the tail filter; three later full
  runs passed with exit 0, so it reads as a flake, not a regression.
- `app/Atelier/.build/debug/Atelier --selftest` -> exit 0, `SELFTEST: ALL PASS`. GROUP-LEVEL RUN,
  shared with TASK-003.
- GitNexus `detect_changes()` -> 3 changed files: `DESIGN.md` (TASK-001, not mine),
  `AppModel.swift`, and `AtelierApp.swift`. Ten affected processes, all zoom paths already expected
  to change.

Re-verified after the review fix:
- GitNexus `impact({target: "updateForCurrentDisplay", direction: "upstream"})` -> risk LOW, 2
  direct callers, both constructors: `AppModel.init` and `AtelierZoomModel.init`. No process
  affected at the symbol level.
- `swift build --package-path app/Atelier` -> exit 0.
- `swift test --package-path app/Atelier` -> exit 0, 471 tests in 46 suites passed.
- `app/Atelier/.build/debug/Atelier --selftest` -> exit 0, `SELFTEST: ALL PASS`.
- `rg -n "terminalScale|editorScale|appTextScale" app/Atelier/Sources/Atelier/App/AtelierApp.swift`
  -> 10 hits, unchanged.
- `rg -n "UserDefaults.standard" app/Atelier/Sources/Atelier/App/AtelierApp.swift` -> exit 1, no
  match.
- GitNexus `detect_changes()` -> same 3 changed files and the same ten zoom processes. The fix added
  no new affected process.

Known gap, left alone on purpose:
- Restoring a persisted manual zoom above the focus threshold at launch does not enter focus mode.
  The existing display-swap restore has the same gap, and the spec forbids changing the focus mode
  rules, so the behavior was not touched.
