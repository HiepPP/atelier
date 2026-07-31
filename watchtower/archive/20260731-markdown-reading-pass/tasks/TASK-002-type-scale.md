# TASK-002 Add MarkdownTypeScale and route rhythm through it

Group: A
Class: risky

## Brief

Goal: Replace every absolute line-spacing value in the Markdown builder with one resolved type
scale. The line-height ratio must then hold its shape across the whole text-scale and zoom range.

Change: Add `MarkdownTypeScale`, resolve it once per document build, and read every `lineSpacing`
argument from it.

Why this matters: `NSParagraphStyle.lineSpacing` adds extra space on top of the font's own line
height. A flat 8 points is a large share of that total when body text is 10.8 points, and a small
share when body text is 32 points. So one rule produces loose text at one end of the range and
cramped text at the other.

How:

- Add `nonisolated struct MarkdownTypeScale: Sendable` next to `MarkdownRhythm` in the builder file.
- Store the resolved body size and the display scale. Give it one method that converts a target
  ratio and a font into a line-spacing value:
  `max(0, snapped(font.pointSize * ratio - font.lineHeight, displayScale: displayScale))`.
- Reuse `AtelierFontScaling.snapped` for the snap, matching how `MarkdownRhythm` already snaps `u`.
- Add named ratio constants: prose `1.62`, list `1.55`, tableCell `1.45`, code `1.35`,
  displayHeading `1.16`, heading `1.30`.
- Build the scale once in `MarkdownAttributedDocumentBuilder.build`, beside the existing rhythm
  value, and thread it to every `append*` helper that already takes `rhythm`.
- Replace every `lineSpacing:` argument that passes `AtelierMetrics.spaceS`, `AtelierMetrics.spaceXS`,
  or a literal, with the matching scale call. Use the font that block actually renders with, not the
  body font, so headings and code get their own correct value.
- Leave `before:` and `after:` values alone. TASK-004 owns those.
- Log nothing. Allocate nothing in a draw, layout, or per-row path. The scale resolves during
  document construction only.

Files:

- [app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift](app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift):
  add `MarkdownTypeScale`, thread it through `build` and every `append*` helper, and replace every
  absolute `lineSpacing:` argument.
- [app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift](app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift):
  add a test that resolves the ratio at three sizes.

Expected result:

- No absolute line-spacing value remains in a paragraph style in the builder.
- The resolved prose line-height ratio is 1.62 at transcript scale 0.8, at 1.3, and at `editorSize`
  under 2.0 zoom, within one snapped device pixel.
- Existing native-render tests still pass, updated only where they asserted an old spacing value.

Prompt:

```text
Read docs/superpowers/specs/2026-07-31-markdown-reading-pass-design.md section 1 before starting.
Record the measured line-height ratio at the three sizes in the outcome sidecar.
The spec asks for that measurement, because the baseline drift numbers were estimated.
```

## Verify

- `rg -n "lineSpacing: AtelierMetrics" app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift` -> no match.
- `rg -n "struct MarkdownTypeScale" app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift` -> one match.
- `swift test --package-path app/Atelier --filter markdownTypeScaleRatio` -> the new test passes and
  asserts the prose ratio at three body sizes.
- `swift build --package-path app/Atelier` -> build succeeds with no new warnings.
- `swift test --package-path app/Atelier` -> all tests pass.
