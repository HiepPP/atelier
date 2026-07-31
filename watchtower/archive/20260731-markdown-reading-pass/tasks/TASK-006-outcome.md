# TASK-006 Outcome

## Outcome

Status: DONE

Changed:

- Capped `AgentResponseQuestionView` at `AtelierMetrics.transcriptMaxWidth` in
  [app/Atelier/Sources/Atelier/Agent/AgentResponsesView.swift](app/Atelier/Sources/Atelier/Agent/AgentResponsesView.swift).
  It was `maxWidth: .infinity` while the answer capped at 680, so a wide overlay showed two right
  edges on one card.
- Added the `agentResponseQuestionScale` test in
  [app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift](app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift).
- Corrected the question text-scale rule in [DESIGN.md](DESIGN.md).

Corrected finding:

- The design spec claimed the question was fixed at `headline` 16 while the answer body reached
  17.55, so the question read smaller than the answer. That is wrong, and no code change was needed.
  `.atelierFont` resolves its size through `AtelierScaledFontModifier`, which reads
  `\.atelierZoomScale` at
  [app/Atelier/Sources/Atelier/Theme/AtelierTheme.swift](app/Atelier/Sources/Atelier/Theme/AtelierTheme.swift)
  line 230. The transcript container sets that environment value to `zoomScale * textScale`, so the
  question already scales with the transcript. Both sizes move by the same factor, so `headline`
  stays above `body` at every step of the 0.8 to 1.6 range.
- The spec's Verify line asked for one assertion per text scale. That would restate one ratio three
  times, so the line now says the base-size comparison covers the range. The test still checks the
  three scale values.

Contract:

- The question stays plain text, keeps the 3-line clamp, the disclosure control, the pointer cursor
  from its button style, and its accessibility labels.
- Both the question and the answer stay leading-aligned. Neither measure is centered.
- Panel chrome, header height, and control metrics are unchanged.

Reopened and fixed after TASK-008:

- The first fix capped the question's inner content at `transcriptMaxWidth`, then applied the
  `spaceM` leading and `spaceS` trailing padding outside that frame. The container came out 700
  points wide against the answer's 680, so the card still showed two right edges. Measured from a
  window capture: question fill at 1132.5 points, answer content at 1111.0 points.
- The frame now sits after the padding, so the cap applies to the outer edge. Re-measured on the
  same surface: question fill at 1112.5 points, answer content at 1111.0 points. The 1.5 point
  difference is antialiasing on the fill edge.

Verified:

- `rg -n "transcriptMaxWidth" app/Atelier/Sources/Atelier/Agent/AgentResponsesView.swift` -> one
  match at line 629, the question container.
- `swift test --package-path app/Atelier --filter agentResponseQuestionScale` -> passed in 0.001
  seconds.
- `swift build --package-path app/Atelier` -> build complete, no new warnings.
- `swift test --package-path app/Atelier` -> 437 tests in 41 suites passed in 9.378 seconds.
- The shared right edge is a visual claim. It is not proved here; TASK-008 owns it.
