# TASK-001 Outcome

## Outcome

Status: DONE

Changed:

- Replaced the file-preview heading rule in [DESIGN.md](DESIGN.md) with two rules: pure heading
  ratios with no minimum clamp, and a face, weight, ink, and tracking rule per level.
- Replaced the vertical spacing rule with two rules: line spacing as a back-solved line-height ratio,
  and three block weight tiers.
- Changed the unordered list marker from an accent glyph to a secondary glyph, and changed the depth
  fade to start from the secondary label color.
- Changed inline code from an accent block to primary ink on a `raised` fill, and named why.
- Changed the table header from an accent wash to a stronger `raised` fill.
- Changed the pure inline-code table cell chip to the same `raised` fill.
- Added an accent budget rule naming the six remaining terracotta jobs.
- Added three Agent Responses rules: the question measure, the question text scale, and the pinned
  panel-level section bar with its passive behavior rule.

Contract:

- No token was added to the Typography, Spacing, or Color tables.
- Every other Markdown rule is unchanged, including the layout-pass H1 and H2 rule, the lede, the
  front-matter masthead, the outline rail, code cards, figures, Mermaid, and footnotes.

Verified:

- `rg -n "1.62|1.25u|1.75u" DESIGN.md` -> matched at lines 1016, 1020, and 1022.
- `rg -n "transcriptMaxWidth" DESIGN.md` -> matched the metrics row at line 123 and the new question
  measure rule at line 1228.
- `rg -n "### Spacing" -A 12 DESIGN.md` -> the table still lists exactly six tokens.
- `git status --short` -> `DESIGN.md` is the only modified tracked file. The untracked entries are
  this plan's own files and the design spec.
