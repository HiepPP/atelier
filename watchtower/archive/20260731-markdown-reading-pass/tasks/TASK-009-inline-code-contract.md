# TASK-009 Update the contract for unfilled inline code and quiet panel chrome

Group: docs
Class: docs

## Brief

Goal: Update [DESIGN.md](DESIGN.md) before the code changes in this round. Two rules change: inline
code loses its fill, and the response header stops using solid accent buttons.

Why: an on-screen pass found that a neutral chip is still a chip. The fill samples `#D5D0C9` against
a `#F8F7F4` page, and every run carries a 12 point kern on both sides, so a code-heavy paragraph
reads as a mosaic of grey blocks. See
[watchtower/tasks/TASK-008-outcome.md](watchtower/tasks/TASK-008-outcome.md).

How:

- Rewrite the inline code rule. Inline code renders as JetBrains Mono at `0.92` of the surrounding
  body size, in primary ink, with no fill, no outline, and no underline. The face carries the
  distinction. State that no horizontal reservation is added, because there is no fill to clear, so
  punctuation after a code run sits tight against it.
- Delete the rule about expanding the accent fill around inline code and the rule about sizing that
  fill from the run's font box. Both describe a fill that no longer exists.
- Rewrite the pure inline-code table cell rule. With no fill there is nothing to zebra-stripe, so
  the rule becomes: a code run inside a table cell wraps by character like any other long token and
  needs no continuous-chip treatment.
- Keep the JetBrains Mono rule for fenced code, inline code, code-card labels, and code-only cells.
- Keep the color-swatch rule for hex tokens.
- Add a response header rule to the Agent Responses section: header controls use the quiet ghost
  style. At most one control may carry a filled accent, and only when it is the primary action for
  the panel's current state. A row of filled accent buttons above a deliberately quiet body spends
  the accent budget on chrome.
- Add a response outline rule to the Agent Responses section: when the panel is wide enough to keep
  the answer on its readable measure and still fit the rail, show the same trailing On This Page
  outline that Markdown Preview uses. Hide it when the panel is too narrow. The pinned section bar
  and the rail follow the same relationship they already have in Preview: the bar covers the layouts
  where the rail is hidden.

Files:

- [DESIGN.md](DESIGN.md): rewrite the inline code rules, rewrite the table cell chip rule, add two
  Agent Responses rules.

Expected result:

- [DESIGN.md](DESIGN.md) describes unfilled inline code, quiet response header chrome, and the
  response outline rail.
- No token table gains a row.
- No code file changes in this TASK.

## Verify

- `rg -n "atelierInlineCode|accent fill" DESIGN.md` -> no rule describes an inline code fill.
- `rg -n "On This Page" DESIGN.md` -> matches both the Preview rule and the new Agent Responses rule.
- `git status --short -- DESIGN.md` -> DESIGN.md is the only changed file for this TASK.
