# TASK-006 Outcome

## Outcome

Status: DONE

Changed:
- `app/Atelier/Sources/Atelier/Settings/AtelierSettingsView.swift` reads
  `@Environment(AtelierAppearanceModel.self)` beside the existing zoom environment.
- Added an "Appearance" section with the `textformat.size` symbol as the first section in the
  scroll content, above Workspace.
- Rows in order: App text size, Editor text size, Terminal text size, Zoom with Reset, a hairline,
  Code ligatures toggle plus caption, Menu bar item toggle plus caption, a hairline, and the
  "Reset appearance" button plus caption.
- Added one private `AtelierSettingsStepperRow` view inside the same file. All four scale rows share
  it. Its optional `resetAction` renders the Zoom row's Reset button, so no second row type exists.
- Added private `textScaleRow(title:scale:onChange:)` and `caption(_:)` helpers in the view.
- No new shared component file. Workspace, Resource Safety, and the display sizing picker are
  unchanged.

Contract:
- Both surfaces stay on one owner. Text sizes call `zoom.setAppTextScale`, `zoom.setEditorTextScale`,
  and `zoom.setTerminalTextScale`; zoom calls `zoom.zoomIn`, `zoom.zoomOut`, and `zoom.reset`; the
  reset button calls `zoom.resetAppearance()`. The two flags bind to `appearance.codeLigaturesEnabled`
  and `appearance.showsMenuBarExtra`.
- Step math goes through `AtelierAppearancePolicy.clampedTextScale`, and every percent label goes
  through `AtelierAppearancePolicy.percentLabel`, so the Settings window and the menu bar panel
  cannot drift.
- Discrete steppers only. One click is one mutation, so no slider drag can flood the view tree.
- Pointer cursor: the stepper buttons, the Zoom Reset button, and "Reset appearance" use
  `AtelierGhostButtonStyle()`, which already ends in `.atelierPointerCursor()`. Both new Toggles carry
  `.atelierPointerCursor()` directly. Nothing double-applies it.
- Layout stays inside the fixed 460-point settings width: each row is an `HStack` with a
  `Spacer(minLength:)`, and every caption uses `.fixedSize(horizontal: false, vertical: true)`.
- No state is mutated from a layout-derived value, and no force unwrap, `try!`, `as!`, or
  `fatalError` was added.

Verified:
- `swift build --package-path app/Atelier` -> exit code 0. Group-level run, shared by this group.
- `swift test --package-path app/Atelier` -> "Test run with 483 tests in 47 suites passed after
  16.596 seconds". Group-level run. Two earlier runs showed timing flakes in "Pre-commit whisper"
  and "File watcher delivery" while parallel groups were compiling; both suites passed alone
  (`--filter PrecommitWhisper` -> 9 tests passed, `--filter "FileWatcherDelivery|GitRefreshThrottle"`
  -> 15 tests passed) and the clean full run passed. The flakes are load-sensitive timing tests, not
  this change.
- `app/Atelier/.build/debug/Atelier --selftest` -> "SELFTEST: ALL PASS", exit code 0. Group-level run.
- `xcrun swiftc -parse app/Atelier/Sources/Atelier/Settings/AtelierSettingsView.swift` -> exit code 0.
- `rg -n "Appearance|showsMenuBarExtra|resetAppearance" app/Atelier/Sources/Atelier/Settings/AtelierSettingsView.swift`
  -> section title line 23, `$appearance.showsMenuBarExtra` toggle, `zoom.resetAppearance()` action.
- `rg -n "AtelierGhostButtonStyle" app/Atelier/Sources/Atelier/Settings/AtelierSettingsView.swift`
  -> 3 hits: the Reset appearance button, the Zoom Reset button, and the shared step button.
- GitNexus `impact` on `AtelierSettingsView`, direction upstream -> risk LOW, 1 direct dependent,
  0 affected processes.
- `git diff --stat` -> 1 file changed, 173 insertions, no other file touched.
- `app/Atelier/scripts/build_and_run.sh run` -> NOT RUN by this builder. The main session owns the
  single launch after every group finishes.
- Manual check, needs a person at the screen: open Settings, set App text size to 115%, and confirm
  the menu bar panel shows 115% on the App row. No screenshot or Computer Use was used; the plugin
  is not installed.
