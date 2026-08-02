# TASK-003 Menu bar item and appearance panel

Group: app-shell
Class: code

## Brief

Goal: Add one Atelier item to the macOS menu bar. Clicking it opens a small panel that changes the
appearance settings and shows the current values.

Change: a new `MenuBarExtra` scene with `.menuBarExtraStyle(.window)` renders a 300-point panel.

How:

- Create [app/Atelier/Sources/Atelier/Settings/AtelierMenuBarView.swift](app/Atelier/Sources/Atelier/Settings/AtelierMenuBarView.swift):
  - `struct AtelierMenuBarView: View` reads `@Environment(AtelierZoomModel.self)` and
    `@Environment(AtelierAppearanceModel.self)`.
  - Width is `300`. Use `AtelierTheme` colors, `AtelierMetrics` spacing, and `.atelierFont` sizes.
  - Section "Text Size" with three rows: App, Editor, Terminal. Each row has a label, a minus
    button, the percent value from `AtelierAppearancePolicy.percentLabel`, and a plus button. A
    click moves the value by one `textScaleStep`. Disable a button at the range end.
  - Section "Zoom" with one row: minus, the percent of `zoom.manualScale`, plus, and a Reset
    button. Wire them to `zoom.zoomOut()`, `zoom.zoomIn()`, and `zoom.reset()`. Disable using
    `zoom.canZoomOut` and `zoom.canZoomIn`.
  - Section "Display" with the `DisplaySizingMode` picker bound to `zoom.sizingMode`, and a
    "Focus mode" toggle wired to `zoom.isFocusMode` and `zoom.toggleFocusMode()`.
  - Section "Code" with a "Code ligatures" toggle bound to `appearance.codeLigaturesEnabled`, and a
    caption: "The terminal updates now. The editor updates the next time the file opens."
  - Section "Agent" with an agent response text size row, using
    `zoom.agentResponseTextScale` and `zoom.setAgentResponseTextScale(_:)`, stepped by
    `AgentResponseTextSizePolicy`.
  - Section "System" with the resource safety toggle, using
    `@AppStorage(ResourceWatchdog.settingsKey)`, and the same short caption used in the Settings
    window.
  - Footer row with three actions: "Reset Appearance" calls `zoom.resetAppearance()`, a
    `SettingsLink` labelled "Settings...", and "Quit Atelier" calls
    `NSApplication.shared.terminate(nil)`.
  - Use `AtelierGhostButtonStyle()` for the quiet buttons. It already supplies the pointer cursor,
    so do not add `.atelierPointerCursor()` beside it. Add `.atelierPointerCursor()` to each Toggle
    and Picker.
  - Give every icon-only button an accessibility label and help text.
- Edit [app/Atelier/Sources/Atelier/App/AtelierApp.swift](app/Atelier/Sources/Atelier/App/AtelierApp.swift):
  - Add a `MenuBarExtra` scene after the `Settings` scene:

```swift
MenuBarExtra(
    "Atelier",
    systemImage: "slider.horizontal.3",
    isInserted: menuBarExtraVisibility
) {
    AtelierMenuBarView()
        .environment(model.zoom)
        .environment(model.appearance)
}
.menuBarExtraStyle(.window)
```

  - `menuBarExtraVisibility` is a `Binding<Bool>` over `model.appearance.showsMenuBarExtra`.
  - Do not change the `WindowGroup`, the commands, or the window toolbar style.

Files:

- [app/Atelier/Sources/Atelier/Settings/AtelierMenuBarView.swift](app/Atelier/Sources/Atelier/Settings/AtelierMenuBarView.swift): new panel view.
- [app/Atelier/Sources/Atelier/App/AtelierApp.swift](app/Atelier/Sources/Atelier/App/AtelierApp.swift): new `MenuBarExtra` scene.

Expected result:

- The menu bar shows one Atelier item.
- The panel changes app, editor, terminal, and zoom sizes, and each change shows in the window at
  once.
- Quitting and relaunching keeps every value.

Prompt:

```text
Follow $swiftui-expert-skill. Build the panel from AtelierTheme and AtelierMetrics tokens only. Use
steppers, not sliders. Every clickable control must carry the pointer cursor, directly or through
AtelierGhostButtonStyle.
```

## Verify

- `swift build --package-path app/Atelier` -> exit code 0.
- `rg -n "MenuBarExtra|menuBarExtraStyle" app/Atelier/Sources/Atelier/App/AtelierApp.swift` -> the
  scene and the window style exist.
- `rg -n "AtelierGhostButtonStyle|atelierPointerCursor" app/Atelier/Sources/Atelier/Settings/AtelierMenuBarView.swift`
  -> every control uses one of the two, so the pointer cursor rule holds.
- `app/Atelier/scripts/build_and_run.sh run` -> the app launches with no crash report in
  `~/Library/Logs/DiagnosticReports/`.
- Manual check, needs a person at the screen: click the menu bar item, press plus on Terminal text
  size three times, and confirm the terminal text grows while the sidebar text stays the same.
