# TASK-005 Code ligature toggle

Group: center-typography
Class: risky

## Brief

Goal: Let the user turn JetBrains Mono contextual alternates on or off. The terminal applies the
change at once. The editor and the Markdown preview apply it the next time the file opens.

Change: `AtelierTypography` reads a stored flag instead of a constant, and the terminal rebuilds its
font when the revision changes.

Risk note: `AtelierTypography.codeFont` caches fonts by size and is called from draw and layout
paths. A wrong change here allocates fonts per draw. Clear the caches only when the flag changes,
never inside `codeFont`.

How:

- Edit [app/Atelier/Sources/Atelier/Theme/AtelierTheme.swift](app/Atelier/Sources/Atelier/Theme/AtelierTheme.swift):
  - Change `static let codeFontLigaturesEnabled` to `static private(set) var
    codeFontLigaturesEnabled`.
  - Add `static func setCodeFontLigatures(_ enabled: Bool)`. It returns early when the value did not
    change, assigns it, and clears `codeFontCache` and `plainCodeFontCache`.
  - Keep `codeFont(size:ligatures:)` and `makeCodeFont` unchanged. Both caches stay keyed by size.
- Edit [app/Atelier/Sources/Atelier/Settings/AtelierAppearanceSettings.swift](app/Atelier/Sources/Atelier/Settings/AtelierAppearanceSettings.swift):
  - In `AtelierAppearanceModel`, call `AtelierTypography.setCodeFontLigatures(_:)` when
    `codeLigaturesEnabled` changes, and once during init so a stored `false` applies at launch.
- Edit [app/Atelier/Sources/Atelier/Terminal/TerminalController.swift](app/Atelier/Sources/Atelier/Terminal/TerminalController.swift):
  - Add a `codeFontRevision: Int` parameter to `updateScale`, with a stored
    `appliedCodeFontRevision` on the controller.
  - Rebuild the font when the size changed or the revision changed. Keep the existing early return
    when nothing changed, so a normal layout pass still does no work.
- Edit [app/Atelier/Sources/Atelier/Terminal/TerminalRepresentable.swift](app/Atelier/Sources/Atelier/Terminal/TerminalRepresentable.swift):
  - Add a `codeFontRevision: Int` property and forward it to `updateScale`.
- Edit [app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift](app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift):
  - Read `@Environment(AtelierAppearanceModel.self)` and pass `appearance.codeFontRevision` into
    `TerminalView`.
- Do not add a live refresh path for the editor or the Markdown preview in this TASK. The caption in
  the menu bar panel and in the Settings window states the reopen rule.

Files:

- [app/Atelier/Sources/Atelier/Theme/AtelierTheme.swift](app/Atelier/Sources/Atelier/Theme/AtelierTheme.swift): settable flag and cache reset.
- [app/Atelier/Sources/Atelier/Settings/AtelierAppearanceSettings.swift](app/Atelier/Sources/Atelier/Settings/AtelierAppearanceSettings.swift): applies the flag to typography.
- [app/Atelier/Sources/Atelier/Terminal/TerminalController.swift](app/Atelier/Sources/Atelier/Terminal/TerminalController.swift): revision-aware font rebuild.
- [app/Atelier/Sources/Atelier/Terminal/TerminalRepresentable.swift](app/Atelier/Sources/Atelier/Terminal/TerminalRepresentable.swift): carries the revision.
- [app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift](app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift): supplies the revision.

Expected result:

- Turning ligatures off redraws the terminal with plain glyphs at once.
- Turning them back on restores the ligature glyphs.
- The stored value applies at the next launch without a toggle.

Prompt:

```text
Follow $swiftui-expert-skill. Run GitNexus impact on AtelierTypography.codeFont before editing.
Never allocate a font inside a draw or layout path. Clear the font caches only inside
setCodeFontLigatures.
```

## Verify

- `swift build --package-path app/Atelier` -> exit code 0.
- `swift test --package-path app/Atelier` -> every test passes.
- `rg -n "setCodeFontLigatures" app/Atelier/Sources/Atelier/Theme/AtelierTheme.swift` -> the setter
  exists and is the only place that clears the caches.
- `rg -n "codeFontCache.removeAll|plainCodeFontCache.removeAll" app/Atelier/Sources` -> both matches
  sit inside `setCodeFontLigatures`.
- `app/Atelier/scripts/atelier-doctor status --json` after 20 idle seconds -> `cpuPercent` stays
  between 0.2 and 2.
- Manual check, needs a person at the screen: open a terminal, type `x != y --> z`, toggle
  "Code ligatures" off, and confirm the arrow and the not-equal glyph split into plain characters.
