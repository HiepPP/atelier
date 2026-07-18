# TASK-004 Outcome

## Outcome

Status: DONE

Changed:

- Added Back, Forward, and Reopen Closed Tab to the typed action registry.
- Added live action availability and handlers backed by `TerminalTabsModel`.
- Added native menu shortcuts for Control-minus, Control-Shift-minus, and Command-Shift-T.
- Added leading Back and Forward tab-bar controls with labels, help, and availability values.
- Styled preview tab titles without adding another icon and exposed the Preview accessibility value.
- Added deterministic registry, palette, and navigation availability coverage.

Verified:

- `swift test --package-path app/Atelier --filter AtelierActionRegistryTests` -> 4 tests passed.
- `swift test --package-path app/Atelier --filter AtelierPalettePresentationTests` -> 4 tests passed.
- `swift test --package-path app/Atelier --filter TerminalTabsNavigationTests` -> 11 tests passed.
- `swift build --package-path app/Atelier` -> build completed successfully.
- `swift test --package-path app/Atelier` -> 103 tests passed across 12 suites.
- `app/Atelier/.build/debug/Atelier --selftest` -> `SELFTEST: ALL PASS`.
- `app/Atelier/scripts/build_and_run.sh run` -> built, ad hoc signed, installed, and launched Atelier.
- `git diff -- app/Atelier/Package.swift` -> no package changes.
- `git diff --check` -> no whitespace errors.

Native evidence:

- 760 x 512 content check -> Back and Forward stayed visible with nine terminal tabs in the horizontal scroller; Response and New Terminal controls stayed visible.
- 1440 x 900 content check -> Explorer preview replacement, edit promotion, Back, Forward, and Reopen Closed Tab all worked.
- Control-minus and Control-Shift-minus traversed README.md and .gitignore preview history.
- Command-Shift-T reopened the newest closed permanent file.
- Native View menu exposed Back, Forward, and Reopen Closed Tab with live availability.
- Command palette exposed all three actions, shortcut labels, and unavailable states.
- Accessibility tree exposed Back and Forward availability plus `Selected, Preview` for preview tabs.
- Narrow screenshot: `/tmp/atelier-navigation-history-760x512.jpeg`.
- Wide screenshot: `/tmp/atelier-navigation-history-1440x900.jpeg`.
- Temporary native edit fixture -> removed after verification.
