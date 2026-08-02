# TASK-005 Outcome

## Outcome

Status: DONE

Changed:
- `app/Atelier/Sources/Atelier/Theme/AtelierTheme.swift`: `codeFontLigaturesEnabled` went from
  `static let` to `static private(set) var`. Added `static func setCodeFontLigatures(_ enabled: Bool)`,
  which returns early on no change, assigns the flag, then clears `codeFontCache` and
  `plainCodeFontCache`. `codeFont(size:ligatures:)` and `makeCodeFont(size:ligatures:)` are
  byte-for-byte unchanged, and both caches stay keyed by size alone.
- `app/Atelier/Sources/Atelier/Settings/AtelierAppearanceSettings.swift`: the `codeLigaturesEnabled`
  `didSet` now calls `AtelierTypography.setCodeFontLigatures(...)` before bumping `codeFontRevision`.
  `init` calls the same setter after reading the stored value, because an assignment inside `init`
  skips `didSet` and a stored `false` would otherwise never reach typography.
- `app/Atelier/Sources/Atelier/Terminal/TerminalController.swift`: added
  `private var appliedCodeFontRevision = 0` and a `codeFontRevision: Int` parameter on `updateScale`.
  The old local `fontChanged` was renamed `sizeChanged` and a `revisionChanged` term was added, so
  the guard is now `sizeChanged || smoothingChanged || revisionChanged`. The font is re-read when the
  size or the revision moved, and is assigned only when the resolved `NSFont` actually differs.
  A second gate, `didChange`, starts as `sizeChanged || smoothingChanged` and turns true only in the
  branch that assigns `terminal.font`. `setNeedsDisplay` and `layoutSubtreeIfNeeded` now sit behind
  `guard didChange else { return }`. `appliedCodeFontRevision` is still written unconditionally, so
  the next call short-circuits on the outer guard. See the review-fix note below.
- `app/Atelier/Sources/Atelier/Terminal/TerminalRepresentable.swift`: new `codeFontRevision: Int`
  property, forwarded into `updateScale`.
- `app/Atelier/Sources/Atelier/Terminal/TerminalView.swift`: new `codeFontRevision: Int` property,
  forwarded into `TerminalRepresentable`. NOT in the spec's file list, but unavoidable: `TerminalView`
  is the only link between `TerminalTabs` and `TerminalRepresentable`. No TASK in this plan lists
  this file, so no parallel writer was disturbed.
- `app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift`: reads
  `@Environment(AtelierAppearanceModel.self) private var appearance` and passes
  `appearance.codeFontRevision` into `TerminalView`.
- `app/Atelier/Tests/AtelierTests/DisplaySizingTests.swift`: unchanged. An earlier pass of this TASK
  deleted the `#expect(AtelierTypography.codeFontLigaturesEnabled)` line; the review fix restored it,
  so the file now matches `HEAD` byte for byte and `git status` no longer lists it.
- `app/Atelier/Tests/AtelierTests/AtelierAppearancePolicyTests.swift`: two additions from the review
  fix. `ligaturesOffPersists` now also asserts `!AtelierTypography.codeFontLigaturesEnabled`, which
  covers the model-to-typography wiring. A new test, `codeFontLigatureSetterRoundTrips`, drives
  `setCodeFontLigatures` off and on and restores `true` in a `defer`. That file belongs to TASK-007,
  which is complete; these are additive tests for the symbol TASK-005 introduced.
- No live refresh path was added for the editor or the Markdown preview, as instructed.

Contract:
- `setCodeFontLigatures` is the only writer of the flag and the only place either font cache is
  cleared. `codeFont` still allocates nothing on a cache hit and never clears a cache, so draw,
  layout, and per-row paths are unchanged.
- `AtelierAppearanceModel` is the only caller of the setter. One appearance model exists at runtime,
  so the flag has one owner.
- `updateScale` keeps its early return. A layout pass with an unchanged size, smoothing, and revision
  still does no work and issues no invalidation.
- A revision bump rebuilds the terminal font once per controller and repaints once. A revision bump
  that resolves to an identical font applies nothing and repaints nothing, which is the case for a
  controller created after the user already flipped the flag: its `init` built the font from the live
  flag, so the first `updateScale` has a new revision and no work to do.
- The editor and the Markdown preview pick up the new flag on the next render, which is the
  documented reopen rule.

Verified:
- `impact({target: "codeFont", direction: "upstream"})` -> the `AtelierTypography.codeFont` candidate
  reports MEDIUM risk, 22 impacted symbols, 13 direct callers, across `MarkdownSelectableDocumentView`,
  `FileLineNumberRulerView`, `FileViewer`, and `TerminalController`. Reported as required. The risk is
  accepted because the change touches neither the signature nor the caching: callers see the same
  function and the same cache-hit cost, only the flag it reads can now move.
- `rg -n "setCodeFontLigatures" app/Atelier/Sources/Atelier/Theme/AtelierTheme.swift` -> one match,
  line 194, the setter definition.
- `rg -n "codeFontCache.removeAll|plainCodeFontCache.removeAll" app/Atelier/Sources` -> exactly two
  matches, lines 197 and 198, both inside `setCodeFontLigatures`, which spans lines 194 to 199.
- `swift build --package-path app/Atelier` -> exit 0, "Build complete!".
  GROUP-LEVEL RUN, shared with TASK-004. Re-run after the review fix, still exit 0.
- `swift test --package-path app/Atelier --filter "AtelierAppearancePolicyTests|DisplaySizingTests"`
  -> exit 0, 34 tests in 2 suites passed in 0.832 s. Both suites that read the ligature flag pass
  together under the default parallel runner. REVIEW-FIX RUN.
- `swift test --package-path app/Atelier --no-parallel` -> exit 0, 483 tests in 47 suites passed in
  32.965 s. GROUP-LEVEL RUN, shared with TASK-004, from the pre-review pass.
- `swift test --package-path app/Atelier` (default parallel) -> exit 1 on both review-fix runs, with
  a different failure set each time. Run 1: 7 issues, `PrecommitWhisperTests` "A preempted scan
  releases the fingerprint so the same diff rescans". Run 2: 6 issues, `PrecommitWhisperTests`
  "A changed diff triggers one scan and publishes findings" plus `FileWatcherDeliveryTests`
  "A sustained write burst delivers before the burst ends" at 2.33 s against a 2 s bound. Every
  failing expectation is a wall-clock or debounce bound. `--filter PrecommitWhisperTests` alone ->
  exit 0, 9 tests in 1.374 s. No changed symbol in this group reaches either file. Nondeterministic
  across runs, so a load flake, not a product failure. REVIEW-FIX RUN.
- `app/Atelier/.build/debug/Atelier --selftest` -> exit 0, `SELFTEST: ALL PASS`.
  GROUP-LEVEL RUN, shared with TASK-004. Re-run after the review fix, still `SELFTEST: ALL PASS`.
- `impact({target: "updateScale", direction: "upstream"})` -> LOW risk, 1 impacted symbol,
  `TerminalRepresentable.updateNSView`, 0 affected processes. Run before the `didChange` edit.
- `detect_changes({scope: "unstaged"})` -> `AtelierTypography`, `AtelierTypography.codeFont`,
  `TerminalController.updateScale`, `TerminalRepresentable`, `TerminalView`, and `TerminalTabs` are
  the changed symbols on this group's side. Three affected flows reach `codeFont`:
  `AppendCode -> MakeCodeFont`, `AppendFootnotes -> MakeCodeFont`, and
  `ToggleMermaidSource -> MakeCodeFont`. All three are Markdown render paths, and all three now read
  the live flag on their next render, which matches the documented reopen rule.
- `app/Atelier/scripts/atelier-doctor status --json` after 20 idle seconds -> DEFERRED, not run as
  proof. The live Atelier is PID 51140, started 18:25:29, before the first edit at 18:31:46, so it
  runs the pre-change binary. Launching is forbidden for this builder. Replace this check with:
  after the main session's `build_and_run.sh` launch, wait 20 s, then read `cpuPercent` and confirm
  0.2 to 2 on an otherwise idle machine.
- Manual check, needs a person at the screen: open a terminal, type `x != y --> z`, toggle
  "Code ligatures" off, and confirm the arrow and the not-equal glyph split into plain characters.
  Toggle back on and confirm they rejoin. Not run. No Computer Use plugin on this machine, and
  `atelier-doctor probe` exposes no glyph or font path.

## Review Fixes Applied

Two reviewer findings, both fixed.

### 1. Restored the deleted typography assertion

- Finding: deleting `#expect(AtelierTypography.codeFontLigaturesEnabled)` from
  `DisplaySizingTests.swift:137` was an out-of-scope edit, and the parallel-suite race it claimed does
  not exist on this tree.
- Why the race claim was wrong: both suites that flip the flag restore it in a `defer`
  (`AtelierAppearancePolicyTests.swift`, `AtelierTypography.setCodeFontLigatures(true)`), and every
  test body involved is a synchronous, non-`async`, MainActor-isolated function. `Package.swift`
  sets `.defaultIsolation(MainActor.self)` on both the library target and the test target, so a
  synchronous body has no suspension point and cannot interleave with another MainActor test.
- Fix: restored the assertion and deleted the four-line comment. `DisplaySizingTests.swift` now
  matches `HEAD` exactly.
- Added cover for the symbol this TASK introduced, in `AtelierAppearancePolicyTests`:
  `codeFontLigatureSetterRoundTrips` drives `setCodeFontLigatures(false)` then `(true)` and asserts
  the flag both ways, and `ligaturesOffPersists` now also asserts that setting
  `model.codeLigaturesEnabled = false` reaches `AtelierTypography`.
- Proof: `swift test --filter "AtelierAppearancePolicyTests|DisplaySizingTests"` -> 34 tests, 2
  suites, all pass under the default parallel runner.

### 2. Gated the terminal invalidation on real work

- Finding: a controller built after the user already toggled ligatures saw `appliedCodeFontRevision`
  at 0 against a live revision of 1 or more, so `revisionChanged` was true on the first `updateScale`.
  `init` had already built the font from the live flag, so `terminal.font != font` correctly skipped
  the assignment, yet `setNeedsDisplay` and `layoutSubtreeIfNeeded` still ran. With `sizeChanged` and
  `smoothingChanged` both false, that is an invalidation after a refresh that produced no change,
  which the repo perf rule bans.
- Fix: `var didChange = sizeChanged || smoothingChanged`, set to `true` only inside the branch that
  assigns `terminal.font`, then `guard didChange else { return }` in front of the two invalidation
  calls. `appliedCodeFontRevision = codeFontRevision` stays unconditional, so the no-op path
  short-circuits on the outer guard next time instead of re-testing the same revision.
- Cost removed: one redundant layout pass per controller per revision.
