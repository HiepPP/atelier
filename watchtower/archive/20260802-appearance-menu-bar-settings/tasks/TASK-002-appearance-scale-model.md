# TASK-002 Appearance scale model and persistence

Group: app-shell
Class: risky

## Brief

Goal: Give Atelier one owner for appearance state. Add three text scales, persist them, persist
manual zoom per display, and add the ligature and menu bar visibility flags.

Change: `AtelierZoomModel` gains three text scales and disk persistence. A new small model owns the
two boolean settings.

Risk note: `AtelierZoomModel` feeds every surface and takes part in layout profiles. Run
`impact({target: "AtelierZoomModel", direction: "upstream"})` before editing and report the blast
radius. Do not change the existing zoom range, the caps, the settle delay, or the focus mode rules.

How:

- Create [app/Atelier/Sources/Atelier/Settings/AtelierAppearanceSettings.swift](app/Atelier/Sources/Atelier/Settings/AtelierAppearanceSettings.swift):
  - `nonisolated enum AtelierAppearancePolicy` holds the pure rules and the keys.
    - `minimumTextScale = 0.8`, `maximumTextScale = 1.6`, `textScaleStep = 0.05`,
      `defaultTextScale = 1.0`.
    - `clampedTextScale(_ value: CGFloat) -> CGFloat` clamps to the range, snaps to the step, and
      rounds to two decimals.
    - `percentLabel(_ scale: CGFloat) -> String` returns a whole percent, for example `105%`.
    - Key constants: `appTextScaleKey = "atelier.appTextScale"`,
      `terminalTextScaleKey = "atelier.terminalTextScale"`,
      `editorTextScaleKey = "atelier.editorTextScale"`,
      `manualZoomByDisplayKey = "atelier.manualZoomByDisplay.v1"`,
      `codeLigaturesKey = "atelier.codeLigaturesEnabled"`,
      `menuBarExtraKey = "atelier.showsMenuBarExtra"`.
  - `@MainActor @Observable final class AtelierAppearanceModel`:
    - Init takes `defaults: UserDefaults = .standard`. Keep the reference with
      `@ObservationIgnored`.
    - `var codeLigaturesEnabled: Bool` defaults to `true` when the key is absent. A change writes
      the key and increments `codeFontRevision`.
    - `var showsMenuBarExtra: Bool` defaults to `true` when the key is absent. A change writes the
      key.
    - `private(set) var codeFontRevision: Int`, starts at 0. TASK-005 uses it to rebuild fonts.
- Edit `AtelierZoomModel` in [app/Atelier/Sources/Atelier/App/AtelierApp.swift](app/Atelier/Sources/Atelier/App/AtelierApp.swift):
  - Add an init parameter `defaults: UserDefaults = .standard`. Store it with
    `@ObservationIgnored`. Route every existing read and write of `UserDefaults.standard` in this
    class through it, including the sizing mode and the agent response text scale.
  - Add `private(set) var appTextScale`, `terminalTextScale`, and `editorTextScale`, each loaded
    through `AtelierAppearancePolicy.clampedTextScale` with the default 1.0.
  - Add `setAppTextScale(_:)`, `setTerminalTextScale(_:)`, and `setEditorTextScale(_:)`. Each
    clamps, returns early when the value did not change, assigns, and writes its key.
  - Change the derived values:
    - `chromeScale` is `min(renderScale * appTextScale, chromeMaximumScale)`.
    - `sidebarScale` is `min(renderScale * appTextScale, sidebarMaximumScale)`.
    - `contentScale` is `renderScale * appTextScale`.
    - Add `terminalScale` as `renderScale * terminalTextScale`.
    - Add `editorScale` as `renderScale * editorTextScale`.
  - Persist manual zoom. Load `manualScaleByDisplay` from `manualZoomByDisplayKey` at init as
    `[String: Double]`, clamped to the zoom range. Write the map after `requestScale` settles,
    after `updateForCurrentDisplay` swaps displays, and after `applyLayoutProfileState`.
  - Add `resetAppearance()`. It sets the three text scales back to 1.0, then calls the existing
    `reset()` for zoom. Keep the existing focus mode behavior inside `reset()`.
  - Do not persist inside the zoom settle task's cancellation path.
- Edit [app/Atelier/Sources/Atelier/App/AppModel.swift](app/Atelier/Sources/Atelier/App/AppModel.swift):
  - Add `let appearance: AtelierAppearanceModel` beside the existing `zoom` property and build it in
    the same init, using `environment.layoutProfileDefaults ?? .standard`.
- Edit the scene body in [app/Atelier/Sources/Atelier/App/AtelierApp.swift](app/Atelier/Sources/Atelier/App/AtelierApp.swift):
  - Pass `.environment(model.appearance)` beside `.environment(model.zoom)` on `applicationContent`
    and on the `Settings` scene, so later TASKs can read it.

Files:

- [app/Atelier/Sources/Atelier/Settings/AtelierAppearanceSettings.swift](app/Atelier/Sources/Atelier/Settings/AtelierAppearanceSettings.swift): new policy enum and appearance model.
- [app/Atelier/Sources/Atelier/App/AtelierApp.swift](app/Atelier/Sources/Atelier/App/AtelierApp.swift): zoom model scales, persistence, reset, environment wiring.
- [app/Atelier/Sources/Atelier/App/AppModel.swift](app/Atelier/Sources/Atelier/App/AppModel.swift): owns the appearance model.

Expected result:

- Changing a text scale writes its key at once and survives a relaunch.
- Manual zoom returns after a relaunch on the same display.
- Existing zoom behavior, caps, focus mode, and layout profiles keep working.

Prompt:

```text
Follow $swiftui-expert-skill. Run GitNexus impact on AtelierZoomModel before editing and report the
blast radius. Keep every UI mutation on MainActor. Do not change the zoom range, the chrome cap, the
sidebar cap, or the focus mode rules.
```

## Verify

- `swift build --package-path app/Atelier` -> exit code 0.
- `swift test --package-path app/Atelier` -> every test passes, including
  `LayoutProfileTests` and `DisplaySizingTests`.
- `rg -n "terminalScale|editorScale|appTextScale" app/Atelier/Sources/Atelier/App/AtelierApp.swift`
  -> the three text scales and both new derived values exist.
- `rg -n "UserDefaults.standard" app/Atelier/Sources/Atelier/App/AtelierApp.swift` -> no match,
  because every read and write now goes through the injected `defaults`.
- `app/Atelier/.build/debug/Atelier --selftest` -> self test passes.
