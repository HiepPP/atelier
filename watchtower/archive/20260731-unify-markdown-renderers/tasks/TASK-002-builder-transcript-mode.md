# TASK-002 Add a transcript mode to the builder

Group: A (shares [app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift](app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift) with TASK-003 and TASK-004)

## Brief

Goal: Teach `MarkdownAttributedDocumentBuilder.build` to produce compact transcript output as well as the current document output. One switch, one code path.

Change: `build(document:scale:displayScale:usesDarkAppearance:)` -> the same call plus a `presentation` argument.

How:

- Reuse the existing `AgentMarkdownPresentation` enum. It already has `transcript` and `document` cases.
- Add `presentation: AgentMarkdownPresentation = .document` to `build`. The current preview call site keeps its behavior.
- Derive the base body size from the mode. Document mode keeps `AtelierTypography.editorSize`. Transcript mode uses `AtelierTypography.body`.
- Skip the document-only treatments in transcript mode: the lede paragraph scale, the front matter masthead, and the H3 accent eyebrow color.
- Keep every other block treatment shared. Do not fork a second builder.
- `MarkdownRhythm` already derives spacing from the body font, so transcript spacing shrinks on its own. Check the result and adjust only if a gap looks wrong.
- Read every block case before editing it. The switch runs from line 677 to line 965.

Files:

- [app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift](app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift) (add the presentation argument and the mode-dependent branches)
- [app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift](app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift) (add tests for the transcript mode base size and skipped treatments)

Expected result:

- `build` accepts a presentation argument and defaults to `document`.
- Transcript mode renders body text at `AtelierTypography.body` scaled by the environment scale.
- Transcript mode adds no lede scale and no masthead.
- Every existing builder test still passes without edits.

Prompt:

```text
Run gitnexus impact on MarkdownAttributedDocumentBuilder.build before editing it. Report the blast radius. Then add the presentation argument.
```

## Verify

- `swift build --package-path app/Atelier` -> build succeeds.
- `swift test --package-path app/Atelier` -> all tests pass, including the new transcript mode tests.
- New test: build the same source in both modes -> the transcript document reports a smaller body font size than the document mode one.
- New test: build a source that starts with front matter and an H1 in transcript mode -> no masthead row is emitted.
