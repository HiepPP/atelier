# TASK-001 Update the Markdown design contract

Group: docs
Class: docs

## Brief

Goal: Update [DESIGN.md](DESIGN.md) so the contract describes the new Markdown reading rules before
any code changes. The repo treats [DESIGN.md](DESIGN.md) as the design contract.

Change: Rewrite the Markdown rhythm, heading, block spacing, and accent rules. Add the response card
measure rule and the transcript section bar rule.

How:

- Read [docs/superpowers/specs/2026-07-31-markdown-reading-pass-design.md](docs/superpowers/specs/2026-07-31-markdown-reading-pass-design.md) first.
- In the Editor and Terminal section, replace the current vertical spacing rule. State that line
  spacing is a target line-height ratio back-solved against the font's own line height, resolved
  during document build. Name the six ratios: prose 1.62, list items 1.55, table cells 1.45, code
  lines 1.35, H1 and H2 1.16, H3 and deeper 1.30.
- Replace the heading rule. State that heading sizes are pure ratios of body size with no minimum
  clamps. Give the document ratios 1.85, 1.45, 1.18, 1.00, 0.92 and the transcript ratios 1.45,
  1.28, 1.12, 1.00, 0.92. State that H4 is semibold in foreground ink, and H5 and H6 are semibold
  secondary with `+0.6` tracking.
- Replace the block spacing rule with the three tiers. Flow blocks get `0.5u`. Structure blocks get
  `1.25u`. Break blocks get `1.75u` before and `0.6u` after. Name which blocks sit in each tier.
  State that H3 keeps `1u` before and `0.5u` after.
- Update the accent rules. Inline code uses primary ink on a `raised` fill. List bullets use
  secondary ink fading toward border by depth. The table header uses a stronger `raised` fill with
  semibold weight and light tracking, kept distinct from the zebra row fill. State that terracotta
  stays only on block quote rules, callouts, links, footnote numbers, and the document H3 eyebrow.
- In the Agent Responses section, state that the question container uses the same
  `transcriptMaxWidth` measure as the answer, so the card presents one right edge. State that the
  question scales with the transcript text scale because it is content, not panel chrome.
- In the Agent Responses section, add the pinned section bar rule. One panel-level bar. It shows the
  active heading of the response card that owns the viewport top, plus the reading progress line.
  It mounts only when that answer has two or more headings. It stays passive: no hit testing, no
  animation during passive scroll, no contribution to the measured column width.
- Keep every other Markdown rule unchanged. Do not add tokens to the Typography, Spacing, or Color
  tables.

Files:

- [DESIGN.md](DESIGN.md): rewrite the Markdown rhythm, heading, block spacing, and accent rules;
  add two Agent Responses rules.

Expected result:

- [DESIGN.md](DESIGN.md) describes the target behavior of this plan.
- No token table gains a row.
- No code file changes in this TASK.

## Verify

- `rg -n "1.62|1.25u|1.75u" DESIGN.md` -> matches the new ratio and tier rules.
- `rg -n "transcriptMaxWidth" DESIGN.md` -> matches both the metrics table row and the new question
  measure rule.
- `git status --short -- DESIGN.md` -> DESIGN.md is the only changed file for this TASK.
- `rg -n "### Spacing" -A 12 DESIGN.md` -> the spacing table still lists exactly six tokens:
  `spaceXS`, `spaceS`, `spaceM`, `spaceL`, `spaceXL`, `space2XL`.
