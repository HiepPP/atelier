# TASK-010 Outcome

## Outcome

Status: DONE

## Changed

- Added quiet link underlines and full-strength hover underlines.
- Reused the existing bounds observer to derive reading progress.
- Added a passive one-pixel progress hairline to the outline rail.

## Contract

- Links keep native activation and the pointing-hand cursor.
- Progress reports only when its visible rail pixel changes.
- Passive scrolling adds no observer, animation, or document rebuild.

## Verified

- `swift test --package-path app/Atelier --filter AgentResponsesTests.markdownLinkAndProgress --quiet` passed.
- The test checks real TextKit link glyph geometry and rejects trailing whitespace.
- `markdownOutlineScrollSync` passed.
- Source inspection confirms the existing bounds observer is the sole progress driver.
- Full-window passive scroll moved the native value from `0.5851821360` to `0.8865656793`, selected `Footnotes`, and extended the progress hairline without a visible transition.
- Native hover passed at the full `1710 x 1010` window size. Computer Use before/after captures showed the underline strengthen, and a cursor-inclusive capture showed the pointing-hand cursor. A Quartz `CGEvent` pointer move supplied coordinates because the bundled Computer Use coordinate injector still returned `noWindowsAvailable`.
- `swift build --package-path app/Atelier` and packaged selftest passed.
- Full `swift test --package-path app/Atelier --quiet` later passed all 282 tests after the Git pipe inheritance fix.
- `git diff --check` passed.
