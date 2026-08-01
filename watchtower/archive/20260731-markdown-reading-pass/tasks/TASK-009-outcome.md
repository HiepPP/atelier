# TASK-009 Outcome

## Outcome

Status: DONE

Changed:

- Replaced the two inline code rules in [DESIGN.md](DESIGN.md). Inline code is now JetBrains Mono at
  `0.92` of body size, primary ink, with no fill, no outline, and no underline. The rule names why: a
  terracotta chip stripes the prose and a neutral chip only makes the stripes grey.
- Added a rule banning any horizontal reservation around a code run, so punctuation sits tight and a
  short word between two runs is not boxed.
- Deleted the rule about sizing the fill from the run's font box. It described a fill that no longer
  exists.
- Replaced the pure inline-code table cell rule. With no fill there is nothing to break across a soft
  wrap, so a long path wraps by character like any other unbroken token.
- Added a response header rule: header controls use the quiet ghost style, and at most one control
  may carry a filled accent.
- Added a response outline rule: show the shared On This Page rail when the panel fits
  `transcriptMaxWidth` plus `markdownOutlineWidth`, mark the active row from the same active-heading
  value the section bar uses, and keep outline state session-only.
- Rewrote the section bar rule so the bar and the rail are never both visible, matching how Markdown
  Preview already relates them.

Contract:

- No token was added to the Typography, Spacing, or Color tables.
- The JetBrains Mono rule and the hex color-swatch rule are unchanged.
- Fenced code cards are unchanged.

Verified:

- `rg -n "inline code|inline-code" DESIGN.md` -> five matches, none of which describes a fill. The
  looser `accent fill` grep in the spec matches two unrelated rows, the `accentInk` color token and
  the `AtelierFilledButtonStyle` row, so this precise grep was used instead.
- `rg -c "On This Page" DESIGN.md` -> five matches, covering the metrics row, the Preview rules, and
  the new Agent Responses rule.
- `git status --short -- DESIGN.md` -> DESIGN.md is the only file changed by this TASK.
