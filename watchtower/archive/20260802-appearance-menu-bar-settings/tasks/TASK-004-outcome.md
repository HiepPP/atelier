# TASK-004 Outcome

## Outcome

Status: DONE

Changed:
- `app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift`, `.terminal` case: `TerminalView` now
  receives `scale: zoom.terminalScale` instead of `zoom.contentScale`.
- `app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift`, `.file` case:
  `.environment(\.atelierZoomScale, ...)` now carries `zoom.editorScale` instead of
  `zoom.contentScale`.
- Nothing else moved. The `.gitDiff` case (line 1510), the `.gemma` case (line 1521), and the agent
  response overlay (line 1741) still read `zoom.contentScale`. The tab bar and the status bar were
  not touched.
- `TerminalController.updateScale` was not changed by this TASK. TASK-005 later added a
  `codeFontRevision` parameter to it, which is a separate concern.

Contract:
- Terminal text size follows `renderScale * terminalTextScale`. Nothing else on screen reacts to the
  terminal text scale.
- File tab text size follows `renderScale * editorTextScale`. Nothing else reacts to the editor text
  scale.
- Manual zoom still moves both surfaces, because `renderScale` sits inside each derived value.
- `AtelierZoomModel` stays the single owner of scale math. No second source of truth was added.

Verified:
- `impact({target: "contentScale", direction: "upstream"})` -> LOW risk, 0 impacted symbols,
  0 affected processes. `contentScale` is read directly in view bodies, so no caller had to move.
  `rg -n "contentScale" app/Atelier/Sources` confirms the only other readers are `DiffView.swift`
  (3 sites) and the three TerminalTabs sites the spec said to leave alone.
- `rg -n "zoom.terminalScale|zoom.editorScale" app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift`
  -> exactly one match each: line 1465 `scale: zoom.terminalScale,` and line 1492
  `.environment(\.atelierZoomScale, zoom.editorScale)`.
- `rg -n "scale: zoom.contentScale" app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift`
  -> exit 1, no match.
- `swift test --package-path app/Atelier --filter TerminalTabsNavigationTests` -> exit 0,
  19 tests in 1 suite passed in 0.315 s.
- `swift build --package-path app/Atelier` -> exit 0, "Build complete! (4.90s)".
  GROUP-LEVEL RUN, shared with TASK-005.
- `swift test --package-path app/Atelier --no-parallel` -> exit 0, 483 tests in 47 suites passed in
  32.965 s. GROUP-LEVEL RUN, shared with TASK-005.
- `swift test --package-path app/Atelier` (default parallel) -> exit 1, one failing test:
  `FileWatcherDeliveryTests` "A sustained write burst delivers before the burst ends" at
  `GitRefreshThrottlePolicyTests.swift:203`, `elapsed < .seconds(2)`. Measured 2.56 s, 3.38 s, and
  4.15 s across three runs while the machine sat at load average 9 to 17 with the other builder
  groups running. The same test alone -> exit 0, passes in 1.630 s. `rg` over
  `GitRefreshThrottlePolicyTests.swift` finds no reference to typography, terminal, appearance, or
  zoom scale, so no changed symbol reaches it. This is a wall-clock flake under machine load, not a
  product failure. GROUP-LEVEL RUN.
- `app/Atelier/.build/debug/Atelier --selftest` -> exit 0, `SELFTEST: ALL PASS`.
  GROUP-LEVEL RUN, shared with TASK-005.
- `detect_changes({scope: "unstaged"})` -> the terminal-side changed symbols are `TerminalTabs`,
  `TerminalTabs.body`, `TerminalView`, `TerminalView.body`, `TerminalRepresentable`, and
  `TerminalController.updateScale`. No affected execution flow depends on the old scale source.
- REVIEW-FIX RUN. The review of this group touched only `TerminalController.swift` and two test
  files, so `TerminalTabs.swift` is byte-for-byte unchanged from this TASK's pass. Re-ran this
  TASK's own checks after the fix: both `rg` checks give the same result (`zoom.terminalScale` at
  line 1466, `zoom.editorScale` at line 1494, no `scale: zoom.contentScale`), `swift build` -> exit
  0, and `app/Atelier/.build/debug/Atelier --selftest` -> `SELFTEST: ALL PASS`. The default parallel
  `swift test` fails only on wall-clock bounds in `PrecommitWhisperTests` and
  `FileWatcherDeliveryTests`, with a different failure set on each run and a clean pass when run
  alone. Neither file references terminal, typography, appearance, or zoom scale.
- `app/Atelier/scripts/atelier-doctor status --json` after 20 idle seconds -> DEFERRED, not run as
  proof. The live Atelier is PID 51140, started 18:25:29, which is before the first edit at
  18:31:46, so it runs the pre-change binary and its `cpuPercent` says nothing about this change.
  Launching is forbidden for this builder; the main session owns the single `build_and_run.sh`
  launch. Replace this check with: after that launch, wait 20 s, then read `cpuPercent` and confirm
  0.2 to 2 on a machine that is otherwise idle.
