# TASK-006 Align the response card measure and question size

Group: B
Class: code

## Brief

Goal: Give the response card one right edge, and make the question read above the answer body as the
design contract already requires.

Change: Cap the question container at the answer measure, and scale the question with the transcript
text scale.

Why this matters: `AgentResponseQuestionView` uses `.frame(maxWidth: .infinity)` while
`AgentMarkdownView` caps at `AtelierMetrics.transcriptMaxWidth`. At a wide overlay the card shows two
different right edges. Separately, the question is fixed at `AtelierTypography.headline`, which is 16,
while transcript body reaches 17.55 at the default 1.3 text scale. The question is smaller than the
answer it heads.

How:

- Cap `AgentResponseQuestionView` at `AtelierMetrics.transcriptMaxWidth`, matching the answer column.
- Keep leading alignment on both. Do not center the measure. The card header sets the left edge.
- Pass the transcript text scale into `AgentResponseQuestionView` and multiply the question font size
  by it. The label, the disclosure chevron, and the container paddings keep their own metrics: the
  design contract scales transcript text only.
- Keep the question as plain text. Never render it as Markdown.
- Keep the 3-line clamp, the disclosure control, the pointer cursor from the existing button style,
  and the existing accessibility labels.
- Do not change panel chrome, header height, or control metrics.

Files:

- [app/Atelier/Sources/Atelier/Agent/AgentResponsesView.swift](app/Atelier/Sources/Atelier/Agent/AgentResponsesView.swift):
  cap the question container width and scale the question font.

Expected result:

- The question container and the answer column share one right edge at every overlay width.
- At text scale 1.3 the question renders at 20.8 points against a 17.55 point answer body.
- At text scale 0.8 the question still renders above the answer body size.
- The question stays plain text, still clamps to 3 lines, and still expands.

## Verify

- `rg -n "transcriptMaxWidth" app/Atelier/Sources/Atelier/Agent/AgentResponsesView.swift` -> the
  question container uses the same measure constant as the answer.
- `swift test --package-path app/Atelier --filter agentResponseQuestionScale` -> the new test passes.
  It asserts the question type size stays above the transcript body size. Both scale by the same
  `atelierZoomScale` factor, so one comparison of the base sizes covers every text scale. An
  assertion per scale value would only restate the same ratio.
- `swift build --package-path app/Atelier` -> build succeeds with no new warnings.
- `swift test --package-path app/Atelier` -> all tests pass.
- The visual check of the shared right edge belongs to TASK-008. Do not claim it here.
