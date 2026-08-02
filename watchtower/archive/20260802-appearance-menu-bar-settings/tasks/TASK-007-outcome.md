# TASK-007 Outcome

## Outcome

Status: DONE

Changed:
- Added `app/Atelier/Tests/AtelierTests/AtelierAppearancePolicyTests.swift`. One `@MainActor @Suite`
  named "Atelier appearance policy" with 12 tests, shaped after `AgentResponseTextSizeTests.swift`
  and `LayoutProfileTests.swift`.
- Policy coverage: bounds clamp to 0.8 and 1.6, `.nan` and `.infinity` fall back to 1.0, in-between
  values snap to the nearest 0.05 step (1.07 -> 1.05, 1.03 -> 1.05, 1.02 -> 1.0, 0.94 -> 0.95),
  repeated stepping walks the full range without float drift, the default 1.0 survives a clamp,
  `percentLabel` returns `100%`, `115%`, `80%`, and `160%`, and all six key strings are asserted
  literally.
- Model coverage, each test on its own `UserDefaults(suiteName:)` removed in a `defer` with
  `removePersistentDomain(forName:)`: an empty suite reports ligatures on, the menu bar item
  visible, `codeFontRevision == 0`, and no key written; turning ligatures off writes `false` and a
  second model reads `false`; `codeFontRevision` advances only on a real change; hiding the menu
  bar item writes `false` and reloads as `false` while ligatures stay on.
- Zoom persistence coverage was included. `AtelierZoomModel(windowController: WindowController(),
  defaults: suite)` builds in a test with no live window, because `WindowController.currentScreen()`
  falls back to `NSScreen.main`. The tests set the three text scales, assert the clamp on an
  out-of-range terminal value (0.4 -> 0.8), assert the three stored `Double` values, and assert a
  second model reads them back. One more test proves the multipliers are independent: raising the
  terminal scale moves `terminalScale` and leaves `contentScale` and `editorScale` unchanged.
- No production source was edited. No symbol was modified, so no `impact` run was required.

Review fix (process-global leak):
- The reviewer found that both tests that flip `codeLigaturesEnabled` leaked
  `AtelierTypography.codeFontLigaturesEnabled`. That flag is process-global static state on an enum
  shared by the whole test process, and the `defer` only removed the `UserDefaults` suite.
  `ligaturesOffPersists` ended with the flag on `false`, so a parallel suite reading
  `AtelierTypography.codeFont(size:)` could see ligatures off and fail.
  `AgentResponsesTests.swift:1587` is that reader.
- Fix: both `defer` blocks now call `AtelierTypography.setCodeFontLigatures(true)` before removing
  the suite. `ligaturesOffPersists` carries a comment naming the process-wide flag. Both test bodies
  are fully synchronous, so the restore lands before the main actor can yield and no concurrent test
  can observe the flipped flag.
- The deletion in `DisplaySizingTests.swift` by a parallel group removed one reader, not the leak,
  so it was left in place and not relied on.

Contract:
- The suite fails when a clamp bound, the step size, the default, a percent label, or any of the
  six settings key strings changes by accident.
- The suite also fails when `codeFontRevision` stops being change-gated, when a flag stops
  persisting, or when a text scale stops writing or reading its own key.
- Every assertion uses exact equality, and no test touches `UserDefaults.standard`.

Verified:
- `swift test --package-path app/Atelier --filter AtelierAppearancePolicyTests` -> exit 0,
  12 tests in 1 suite passed. The spec asked for more than five.
- `swift build --package-path app/Atelier` -> exit 0, "ok (build complete)". GROUP-LEVEL RUN for
  this group, which holds TASK-007 only.
- `swift test --package-path app/Atelier` -> exit 0, 483 tests in 47 suites passed, including the
  new suite. GROUP-LEVEL RUN. Two earlier attempts aborted with
  "input file ... was modified during the build" for `TerminalTabs.swift` and `AtelierTheme.swift`.
  Those files belong to other groups running in parallel, so that is a build-race failure, not a
  product failure. The next attempt ran clean.
- `app/Atelier/.build/debug/Atelier --selftest` -> exit 0, `SELFTEST: ALL PASS`. GROUP-LEVEL RUN.
- `git status --short -- app/Atelier/Tests` -> two lines,
  `?? app/Atelier/Tests/AtelierTests/AtelierAppearancePolicyTests.swift` and
  ` M app/Atelier/Tests/AtelierTests/DisplaySizingTests.swift`. Only the first line is TASK-007
  work. `git diff` on `DisplaySizingTests.swift` shows a parallel group dropped the
  `codeFontLigaturesEnabled` assertion. That edit was left untouched.

Re-verified after the review fix:
- `swift test --package-path app/Atelier --filter AtelierAppearancePolicyTests` -> exit 0,
  12 tests in 1 suite passed.
- `swift test --package-path app/Atelier --filter "AtelierAppearancePolicyTests|AgentResponsesTests"`
  run 10 times in a row -> 10 for 10 passes, 114 tests in 2 suites each run. The reviewer reproduced
  a failure on run 7 of 8 before the fix.
- `swift build --package-path app/Atelier` -> exit 0, "ok (build complete)".
- `app/Atelier/.build/debug/Atelier --selftest` -> exit 0, `SELFTEST: ALL PASS`.
- `swift test --package-path app/Atelier` -> 483 tests, with wall-clock timing tests flaking under
  the full parallel run: `PrecommitWhisperTests` and `GitRefreshThrottlePolicyTests`. Both pass in
  isolation (`--filter "GitRefreshThrottlePolicyTests|PrecommitWhisperTests"` -> 24 tests passed).
  Pre-existing and unrelated: a baseline full run with
  `AtelierAppearancePolicyTests.swift` moved out of the target failed the same
  `PrecommitWhisperTests` cases (471 tests, 5 issues). The file was restored right after.
