# Learn 20260726 Editorial Markdown Preview Enhancements

## Summary

The plan shipped all ten tasks. Review found two discrepancies: TASK-006 needed native geometry follow-ups, and full-suite verification exposed an unrelated Git pipe hang.

## Per TASK

- TASK-001: Match. GitHub callouts render as selectable native cards. Ordinary quotes stay unchanged.
- TASK-002: Match. Lists preserve capped depth, marker shape, tab stops, and wrapped indents.
- TASK-003: Match. Tables honor delimiter alignment and right-align numeric-majority columns.
- TASK-004: Match. Native block spacing uses one display-scale-snapped rhythm.
- TASK-005: Match. Local figures decode off-main and retain stable placeholder bounds.
- TASK-006: Discrepancy resolved. Initial verification missed gutter clipping and inverted Core Text glyphs. The fix anchors numbers to the used text fragment and corrects the text matrix for flipped contexts.
- TASK-007: Match. Quotes use one cached hanging glyph, and list markers use optical outdent.
- TASK-008: Match. Front matter follows the title, masthead, lede, and remaining metadata order.
- TASK-009: Match. Footnotes use stable reference order and one trailing Notes section.
- TASK-010: Match. Links strengthen on hover, keep the pointing-hand cursor, and reuse the existing scroll observer for progress.

## Plan-Level

- Native verification caught two TASK-006 defects after an initial false-green result.
- Full-suite verification exposed an unrelated concurrent Git pipe EOF hang.
- Marking every pipe endpoint `FD_CLOEXEC` stopped child processes from retaining another command's writer.
- All focused, build, full-suite, self-test, native, runtime, CPU, and diff gates passed before archive.

## Lessons

- Match TextKit drawing tests to the production flipped graphics context.
- Verify generated glyph position, orientation, and copied source separately.
- Treat timing failures as flakes only after isolated and final full-suite passes.
- Keep DONE blocked until every native and deterministic gate passes.
