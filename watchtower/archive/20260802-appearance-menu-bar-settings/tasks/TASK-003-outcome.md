# TASK-003 Outcome

## Outcome

Status: DONE

Changed:
- Added `app/Atelier/Sources/Atelier/Settings/AtelierMenuBarView.swift`. `AtelierMenuBarView` reads
  `@Environment(AtelierZoomModel.self)` and `@Environment(AtelierAppearanceModel.self)`, and is a
  fixed 300 points wide.
- Sections in order: Text Size (App, Editor, Terminal rows), Zoom (window zoom row plus Reset),
  Display (sizing mode Picker and Focus mode toggle), Code (ligatures toggle plus the caption),
  Agent (response text row), System (resource safety toggle plus the Settings-window caption).
- Footer row: "Reset Appearance" calls `zoom.resetAppearance()`, a `SettingsLink` labelled
  "Settings...", and "Quit Atelier" calls `NSApplication.shared.terminate(nil)`.
- One private `AtelierMenuBarStepper` renders minus, percent, plus for all five stepper rows. One
  click is one mutation, so there is no slider and no drag flood. Text rows step by
  `AtelierAppearancePolicy.textScaleStep` and disable at each range end. The Agent row steps
  through `AgentResponseTextSizePolicy`. The Zoom row uses `zoom.canZoomOut` and `zoom.canZoomIn`.
- Added the `MenuBarExtra` scene after `Settings` in `AtelierApp.swift`, with
  `systemImage: "slider.horizontal.3"`, `.menuBarExtraStyle(.window)`, and
  `isInserted: menuBarExtraVisibility`, a `Binding<Bool>` over `model.appearance.showsMenuBarExtra`.
  The scene passes both models into the view.

Contract:
- Both surfaces read one model. The panel owns no copy of any appearance value.
- Every clickable control carries the pointer cursor. Buttons use `AtelierGhostButtonStyle()`, which
  already ends in `.atelierPointerCursor()`, so it is never double-applied. The Picker and all three
  Toggles carry `.atelierPointerCursor()` directly.
- Every icon-only stepper button has an accessibility label and matching help text. The percent text
  is `accessibilityHidden` and re-exposed as the stepper's accessibility value.
- The panel is built only from `AtelierTheme` colors, `AtelierMetrics` spacing, and `.atelierFont`
  sizes. The 300-point width is a private constant in the view, because `AtelierMetrics` lives in
  `Theme/AtelierTheme.swift`, which is outside this group's file list.
- `WindowGroup`, the commands, and `.windowToolbarStyle(.unifiedCompact)` are untouched. The new
  scene adds no commands, so it cannot repeat the earlier launch crash caused by mixing
  FocusedValue-only commands into model-bearing commands.

Verified:
- `swift build --package-path app/Atelier` -> exit 0. GROUP-LEVEL RUN, shared with TASK-002.
- `rg -n "MenuBarExtra|menuBarExtraStyle" app/Atelier/Sources/Atelier/App/AtelierApp.swift` -> the
  scene at line 68 and `.menuBarExtraStyle(.window)` at line 77.
- `rg -n "AtelierGhostButtonStyle|atelierPointerCursor"
  app/Atelier/Sources/Atelier/Settings/AtelierMenuBarView.swift` -> 9 hits. Read the file to confirm
  the split: 5 ghost-styled buttons plus the shared stepper button, and 4 direct pointer-cursor
  calls on the Picker and the three Toggles.
- `swift test --package-path app/Atelier` -> exit 0, 471 tests in 46 suites passed. GROUP-LEVEL RUN,
  shared with TASK-002.
- `app/Atelier/.build/debug/Atelier --selftest` -> exit 0, `SELFTEST: ALL PASS`. GROUP-LEVEL RUN,
  shared with TASK-002.
- All four checks above were re-run after the TASK-002 review fix and still pass. The pointer-cursor
  check was re-confirmed by reading `AtelierMenuBarView.swift` in full, not by grepping it: five
  ghost-styled buttons plus the shared stepper button carry the cursor through
  `AtelierGhostButtonStyle()`, and the Picker and all three Toggles carry `.atelierPointerCursor()`
  directly. Nothing double-applies it.

Launch check, run during the review fix pass:
- `app/Atelier/scripts/build_and_run.sh run` -> exit 0. SwiftLint gate passed, the bundle was ad hoc
  signed, `codesign --verify --deep --strict` reported valid on disk, and the app installed and
  opened. The script's own `pkill -x Atelier` replaced the stale pre-change instance, PID 6968.
- `pgrep -x Atelier` -> a fresh PID 51140 running from `/Applications/Atelier.app`. It stayed up
  past 40 seconds, so the new `MenuBarExtra` scene did not repeat the earlier launch crash caused by
  mixing FocusedValue-only commands into model-bearing commands.
- `find ~/Library/Logs/DiagnosticReports -name 'Atelier*' -newermt '2026-08-02 18:25:00'` -> no
  match. No crash or hang report from this launch.
- `app/Atelier/scripts/atelier-doctor status --json` -> `status: healthy`, snapshot age 0.02 s,
  `heartbeatPaused: false`, heartbeat age 501 ms against the 500 ms ping cadence, `verdicts: []`,
  `lastWriteError: null`. Idle CPU read 0.3% from `ps` at 40 seconds, inside the 0.2-2% band.

Still deferred, needs a person at the screen:
- Click the menu bar item, press plus on Terminal text size three times, and confirm the terminal
  text grows while the sidebar text stays the same. The terminal wiring itself belongs to another
  TASK, so run this check after that group lands. No screenshot or Computer Use path exists on this
  machine, so this is a manual step, not a failure.

Contract mismatch, routed out of this group:
- `DESIGN.md:1371` under "Menu Bar" says the panel "groups rows into Text Size, Display, Code, and
  Actions". The shipped panel has seven groups: Text Size, Zoom, Display, Code, Agent, System, and
  the footer action row. TASK-003 mandates all seven, so the code is correct and the contract line
  is the stale side. `DESIGN.md` is owned by TASK-001 and sits outside this group's file list, so it
  was left untouched. The TASK-001 owner or the main session must rewrite that line to
  "The panel groups rows into Text Size, Zoom, Display, Code, Agent, System, and a footer action
  row."
