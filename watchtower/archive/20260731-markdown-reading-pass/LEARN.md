# Learn 20260731-markdown-reading-pass

## Summary

Discrepancy: 7 found across 14 TASKs. Every code TASK shipped, but three specs described a problem
that did not exist, two shipped fixes were wrong on screen while their tests passed, and one TASK
was never planned at all. The plan's own verification never caught a single visual defect.

## Per TASK

- TASK-001: plan said rewrite the Markdown rhythm, heading, block, and accent rules in
  [DESIGN.md](DESIGN.md) -> shipped that. Mistake: none in the work, but the contract was written
  from a spec that carried two wrong claims, so TASK-004, TASK-006, and TASK-007 each had to correct
  it after the code landed. Fix: a docs-first TASK is still a draft. Plan an explicit reconcile pass
  rather than treating the first write as final.
- TASK-002: plan said thread a separate scale value into every `append*` helper -> shipped it stored
  on `MarkdownRhythm` instead, which every helper already receives. Mistake: none. The spec named a
  mechanism where an outcome would have done. Fix: specify the property the code must have, not the
  parameter list.
- TASK-003: plan said remove the four heading clamps and set pure ratios -> shipped that. `match`.
- TASK-004: plan said put list items on the flow tier at `0.5u` -> shipped `0.25u` per edge, so two
  neighbouring items still sit `0.5u` apart. Mistake: spec gap. It treated a list as a block when a
  list is a group of blocks. Fix: when a tier applies to a repeated element, say whether the value is
  per element or per group. Also shipped a table closing spacer the spec never named, because table
  cells carry no trailing gap.
- TASK-005: plan said move inline code to a neutral fill -> shipped that, and it was the wrong fix.
  The on-screen pass showed a grey chip reads as a mosaic just like a terracotta one. TASK-010 then
  removed the fill entirely. Mistake: the spec assumed the accent was the problem when the chip was.
  Fix: before restyling a decoration, ask whether it should exist.
- TASK-006: plan said the question renders smaller than the answer body -> that claim was false;
  `.atelierFont` already scales with the transcript. The real defect was the measure. Then the first
  fix capped the inner content, leaving the padding outside the frame, so the container came out 700
  points against the answer's 680. Mistake: two in one TASK, one wrong premise and one wrong fix that
  a passing test signed off. Fix: verify a premise in code before writing it into a spec, and measure
  a measure claim on screen.
- TASK-007: plan called cross-card wiring the highest risk in the plan -> the response panel renders
  one card at a time, so that risk did not exist. Mistake: the spec was written without reading the
  panel body. Fix: read the view that owns the state before estimating risk in it.
- TASK-008: plan said the six acceptance points need a plugin that is not installed -> drove all six
  with `CGWindowListCopyWindowInfo`, `screencapture -l`, and a `CGEvent` scroll. Mistake: the plan
  accepted BLOCKED without checking what the machine could already do, and a stale memory note said
  accessibility resize was denied when it now works. Fix: re-test a recorded environment limit before
  planning around it.
- TASK-009: plan said rewrite the inline code and chrome rules -> shipped that. `match`.
- TASK-010: plan said remove the fill, the reservation, and the draw path, and confirm the table cell
  path separately -> shipped that, and the table cell needed no work at all: with no fill there is
  nothing to fragment. Mistake: none. Fix: none.
- TASK-011: plan said reuse the outline rail and gate it on width -> shipped that, but the first
  version measured the scroll view the rail shrinks, which is circular and showed no rail at a width
  that should have had one. Mistake: gating a sibling's visibility on a width the sibling changes.
  Fix: measure the container, never the child.
- TASK-012: plan said the header used a filled accent style on purpose -> the controls used
  `.buttonStyle(.glass)`, which picks up the accent tint. The disabled chevrons looked quiet, which
  hid it. Mistake: the spec named a symptom as the cause. Fix: read the style before naming it.
- TASK-013: never planned. The user reported front matter rendering as a divider plus one run-on
  paragraph. Two independent limits caused it, either alone enough: a 64-line scan bound against a
  186-line block, and a key charset check that ran before unquoting. Mistake: both limits were
  written without a real long document to test against, and the stray-divider fallback had no test.
  Fix: bound a parser against a real worst case, and test the fallback path, not only the happy one.
- TASK-014: plan said widen the key column from measured content -> shipped that, then still wrapped
  on screen, because the share was computed against the nominal 720 point measure while the table
  resolves against the real container, about 690 points here. Mistake: a percentage computed against
  a width that is not the one it resolves against. Fix: when a value resolves against a runtime
  container, compute it against a conservative container, not the nominal one.

## Plan-Level

- The plan verified the wrong things. Build, 441 tests, and self-test passed at every step, and they
  never caught the question overhang, the inline code mosaic, the circular rail gate, the terracotta
  header, or either front-matter break. Every real defect came from a window capture and a pixel
  sample.
- Three of fourteen specs described a problem that did not exist: the question font size, the
  cross-card wiring, and the deliberate accent header. All three were written from the design spec
  rather than from the code. The design phase moved faster than the reading phase.
- Two shipped fixes were wrong on screen while their tests passed, TASK-006 and TASK-011. Both were
  layout arithmetic, and both tests asserted the intent rather than the result.
- Scope grew by two TASKs after the plan was marked DONE, both from the user looking at the app. That
  is the plan working as intended, but it means "all rows DONE" never meant "the surface is right".
- The grouping held. Group A and Group B shared the test file, they were never run in parallel, and
  no write conflict occurred.

## Lessons

- A green test suite is not evidence that a visual change is correct. For any layout or type change,
  capture the window and sample the pixel, and put the before and after values in the outcome.
- Verify a premise against the code before writing it into a spec. Three specs in this plan described
  problems that did not exist, and each cost a TASK's worth of planning.
- Before restyling a decoration, ask whether it should exist. Removing the inline code fill fixed the
  mosaic, the detached punctuation, and the wrapped-path fragments at once, after a whole TASK had
  been spent recolouring it.
- Never gate a sibling's visibility on a width you measure from the view that sibling resizes.
- When a value resolves against a runtime container, compute it against a conservative container.
  A percentage derived from the nominal measure fits the nominal measure and wraps on screen.
- Re-test a recorded environment limit before planning around it. The note that accessibility resize
  was blocked was 13 days old and wrong, and it had already pushed one TASK to BLOCKED.
- `.buttonStyle(.glass)` is accent-tinted, not neutral. A disabled control hides that.
