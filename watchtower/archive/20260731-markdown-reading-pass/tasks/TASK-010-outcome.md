# TASK-010 Outcome

## Outcome

Status: DONE

Changed:

- Inline code in `inlineText` now sets only the code face and primary ink, in
  [app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift](app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift).
  Both `.kern` reservations and the `.atelierInlineCode` attribute are gone.
- Added `MarkdownInlineCodePolicy.fontScale` at `0.92`. The run is sized against the surrounding
  run's own point size, because a monospaced face at the same size reads larger than the sans it
  sits in. It previously inherited the shared code font, which is sized for fenced blocks.
- Removed the inline-code fill draw block from `MarkdownPreviewLayoutManager.drawBackground`, the
  `.atelierInlineCode` attribute key, `MarkdownInlineCodeLayout`, `inlineCodeBackgroundRect`, and the
  `inlineCodePadding` and `inlineCodeHorizontalReservation` fields of
  `MarkdownPreviewDecorationMetrics`.
- Matched `AgentMarkdownInlinePolicy.cachedAttributedString` in
  [app/Atelier/Sources/Atelier/Agent/AgentMarkdownView.swift](app/Atelier/Sources/Atelier/Agent/AgentMarkdownView.swift):
  primary ink, no background.
- Deleted `AgentMarkdownInlinePolicy.pureCodeContent`. It had no callers since the SwiftUI renderer
  was removed, and with no fill there is no chip for it to feed.
- Tests: replaced `markdownInlineCodeNeutralFill` with `markdownInlineCodeHasNoFill`, retired
  `nativeMarkdownInlineCodePadding` which drove the deleted fill draw path and the deleted kern,
  retired `pureInlineCodeContent`, and flipped `inlineCodeStyling` to assert the background is now
  absent.

Contract:

- Fenced code cards are unchanged, including line numbers, the language header, the copy control,
  and syntax highlighting.
- The hex color-swatch behavior inside code runs is unchanged.
- The table cell path needed no change. With no fill there is nothing to break across a soft wrap,
  so the wrapped-path fragmentation TASK-008 found resolved itself.

Verified:

- `rg -n "atelierInlineCode|MarkdownInlineCodeLayout|inlineCodePadding|inlineCodeHorizontalReservation" app/Atelier/Sources/Atelier/` -> no match.
- `rg -n "pureCodeContent" app/Atelier/` -> no match.
- `swift test --package-path app/Atelier --filter markdownInlineCodeHasNoFill` -> passed in 0.031
  seconds. It asserts the run carries a monospaced face and primary ink, no background attribute,
  and no kern on either side.
- `swift build --package-path app/Atelier` -> build complete, no new warnings.
- `swift test --package-path app/Atelier` -> 436 tests in 41 suites passed in 8.177 seconds. The
  count fell from 438 because three fill tests were retired and one was added.

On-screen check, window 426660 at 1700x1000, PID 9861:

- Sampled inside a gap within a code run, above the glyphs, and below the glyphs. All three read
  `#F8F7F4`, identical to the page background and to a plain prose gap. Before this TASK the same
  region read `#D5D0C9`.
- Read on screen: `DesignSync list_projects` and `write_files` render as mono runs inside prose with
  no block behind them. A full stop after `/design-login` and after `_ds_manifest.json` now sits
  tight against the run.

New finding, not in scope, worth a later TASK:

- JetBrains Mono contextual ligatures apply to inline code in prose, so a literal `<!--` renders as
  a left-arrow glyph and `-->` as a right arrow. In an HTML comment quoted inside a sentence this
  misrepresents the source. [DESIGN.md](DESIGN.md) asks for ligatures in the editor and terminal; it
  says nothing about inline runs in prose.
