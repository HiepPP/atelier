# TASK-006 Appearance section in the Settings window

Group: settings-window
Class: code

## Brief

Goal: Put the same appearance controls in the Settings window, plus the toggle that hides the menu
bar item.

Change: `AtelierSettingsView` gains one Appearance section above the existing Workspace section.

How:

- Edit [app/Atelier/Sources/Atelier/Settings/AtelierSettingsView.swift](app/Atelier/Sources/Atelier/Settings/AtelierSettingsView.swift):
  - Read `@Environment(AtelierAppearanceModel.self)` beside the existing zoom environment.
  - Add an `AtelierSettingsSection` titled "Appearance" with the symbol `textformat.size`, placed
    first in the scroll content.
  - Rows in order:
    - App text size: minus, percent label, plus. Uses `zoom.appTextScale` and
      `zoom.setAppTextScale(_:)`.
    - Editor text size: same shape, uses `zoom.editorTextScale`.
    - Terminal text size: same shape, uses `zoom.terminalTextScale`.
    - Zoom: minus, percent of `zoom.manualScale`, plus, Reset. Uses the existing zoom methods.
    - Code ligatures toggle, with the caption "The terminal updates now. The editor updates the
      next time the file opens."
    - Menu bar item toggle bound to `appearance.showsMenuBarExtra`, with the caption "Hide the
      Atelier item in the menu bar. Your settings stay saved."
    - "Reset appearance" button calling `zoom.resetAppearance()`, with the caption "Return zoom and
      all text sizes to 100%."
  - Keep the existing Workspace and Resource Safety sections unchanged, and keep the display sizing
    picker where it is.
  - Extract the size-stepper row into one small private view inside this file, so the three text
    rows share one shape. Do not add a new shared component file.
  - Use `AtelierGhostButtonStyle()` for the stepper buttons and the reset button. It already
    supplies the pointer cursor. Add `.atelierPointerCursor()` to each Toggle.
  - Keep the section under the fixed settings width, so no row clips.

Files:

- [app/Atelier/Sources/Atelier/Settings/AtelierSettingsView.swift](app/Atelier/Sources/Atelier/Settings/AtelierSettingsView.swift): new Appearance section and the shared stepper row.

Expected result:

- The Settings window and the menu bar panel change the same stored values.
- Turning off the menu bar toggle removes the item from the menu bar right away.
- "Reset appearance" returns zoom and the three text sizes to 100%.

## Verify

- `swift build --package-path app/Atelier` -> exit code 0.
- `rg -n "Appearance|showsMenuBarExtra|resetAppearance" app/Atelier/Sources/Atelier/Settings/AtelierSettingsView.swift`
  -> the section, the visibility toggle, and the reset action exist.
- `rg -n "AtelierGhostButtonStyle" app/Atelier/Sources/Atelier/Settings/AtelierSettingsView.swift`
  -> the new buttons use the style that supplies the pointer cursor.
- `app/Atelier/scripts/build_and_run.sh run` -> the app launches with no crash report in
  `~/Library/Logs/DiagnosticReports/`.
- Manual check, needs a person at the screen: open Settings, set App text size to 115%, and confirm
  the menu bar panel shows 115% for the same row.
