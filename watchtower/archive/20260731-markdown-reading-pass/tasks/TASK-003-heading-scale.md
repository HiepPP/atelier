# TASK-003 Remove the heading clamps and set heading ratios

Group: A
Class: code

## Brief

Goal: Make heading hierarchy hold its shape at every text size and zoom, and stop H4 from reading
quieter than the text under it.

Change: Replace the four `max()` clamps in `headingFont` with pure ratios, split by presentation
mode, and give H4 through H6 a real treatment.

Why this matters: the clamps mean the H1-to-body ratio is about 2.6 at transcript scale 0.8 and
1.85 at scale 1.6. Hierarchy changes shape as the reader resizes text. H4 and deeper currently
resolve to body size in secondary ink, so a heading is quieter than its own body copy.

How:

- Change `headingFont(level:bodySize:)` to also take the presentation mode.
- Remove every `max(...)` floor. Use pure ratios of `bodySize`.
- Document ratios: H1 `1.85`, H2 `1.45`, H3 `1.18`, H4 `1.00`, H5 and H6 `0.92`.
- Transcript ratios: H1 `1.45`, H2 `1.28`, H3 `1.12`, H4 `1.00`, H5 and H6 `0.92`.
- Keep the serif face on H1 and H2 in both modes. Keep the system face from H3 down.
- Weight: semibold for H1 through H4. Semibold for H5 and H6 too.
- Update `headingColor`: H4 returns foreground, not secondary. H5 and H6 return secondary.
- Add `+0.6` tracking to H5 and H6 in the same place the builder already adds `-0.5` kern to H1 and
  H2 and `0.6` kern to H3.
- Use the display-heading ratio from `MarkdownTypeScale` for H1 and H2 line spacing, and the heading
  ratio for H3 and deeper. TASK-002 adds both.
- Do not change the layout-pass heading rule, its lead segments, or the document H3 accent eyebrow.

Files:

- [app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift](app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift):
  rewrite `headingFont` and `headingColor`, add H5 and H6 tracking at the heading append site.
- [app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift](app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift):
  add a heading-scale test.

Expected result:

- The H1-to-body size ratio is the same number at transcript scale 0.8 and at 1.6.
- H4 renders at body size, semibold, in foreground ink.
- H5 and H6 render smaller than body, semibold, secondary, with light tracking.
- The H1 and H2 rule still draws in the layout pass and still uses the long and short lead segments.

## Verify

- `rg -n "max\(28|max\(22|max\(AtelierTypography" app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift` -> no match, so no heading clamp remains.
- `swift test --package-path app/Atelier --filter markdownHeadingScale` -> the new test passes. It
  builds one document at two body sizes and asserts the H1-to-body ratio is equal in both.
- `swift test --package-path app/Atelier --filter nativeMarkdownHeadingRule` -> the existing heading
  rule test still passes.
- `swift build --package-path app/Atelier` -> build succeeds with no new warnings.
- `swift test --package-path app/Atelier` -> all tests pass.
