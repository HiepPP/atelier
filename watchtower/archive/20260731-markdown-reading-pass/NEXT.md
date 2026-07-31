# NEXT

## Current Active Plan

- Title: Markdown reading pass across both surfaces
- Slug: 20260731-markdown-reading-pass
- Status: ARCHIVED
- Updated: 2026-07-31

## Tracker

| Order | TASK | Group | Status | Spec | Deps | Context | Notes |
|-------|------|-------|--------|------|------|---------|-------|
| 1 | TASK-001 Update the Markdown design contract | docs | DONE | [watchtower/tasks/TASK-001-design-contract.md](watchtower/tasks/TASK-001-design-contract.md) | - | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Repo rule: DESIGN.md changes before code. Reconcile again in TASK-008. |
| 2 | TASK-002 Add MarkdownTypeScale and route rhythm through it | A | DONE | [watchtower/tasks/TASK-002-type-scale.md](watchtower/tasks/TASK-002-type-scale.md) | TASK-001 | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Largest change. Touches every paragraph style in the builder. |
| 3 | TASK-003 Remove the heading clamps and set heading ratios | A | DONE | [watchtower/tasks/TASK-003-heading-scale.md](watchtower/tasks/TASK-003-heading-scale.md) | TASK-002 | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Also fixes H4 reading quieter than body text. |
| 4 | TASK-004 Apply the three block weight tiers | A | DONE | [watchtower/tasks/TASK-004-block-tiers.md](watchtower/tasks/TASK-004-block-tiers.md) | TASK-002 | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Block quote moves from 0.25u to 1.25u. |
| 5 | TASK-005 Cut the accent budget from nine jobs to five | A | DONE | [watchtower/tasks/TASK-005-accent-budget.md](watchtower/tasks/TASK-005-accent-budget.md) | TASK-002 | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Inline code, list bullets, and table headers go neutral. |
| 6 | TASK-006 Align the response card measure and question size | B | DONE | [watchtower/tasks/TASK-006-card-measure.md](watchtower/tasks/TASK-006-card-measure.md) | TASK-001 | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Question caps at the answer measure and scales with transcript text. |
| 7 | TASK-007 Pin a section bar in the Response tab | B | DONE | [watchtower/tasks/TASK-007-transcript-section-bar.md](watchtower/tasks/TASK-007-transcript-section-bar.md) | TASK-006 | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Only item needing new cross-card wiring. Cut first if it slips. |
| 8 | TASK-008 Drive the on-screen acceptance pass | standalone | DONE | [watchtower/tasks/TASK-008-onscreen-acceptance.md](watchtower/tasks/TASK-008-onscreen-acceptance.md) | TASK-003, TASK-004, TASK-005, TASK-007 | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Manual checks. Needs a human at the screen. No UI automation is installed. |
| 9 | TASK-009 Update the contract for unfilled inline code and quiet chrome | docs | DONE | [watchtower/tasks/TASK-009-inline-code-contract.md](watchtower/tasks/TASK-009-inline-code-contract.md) | TASK-008 | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Second round. Contract first, as the repo requires. |
| 10 | TASK-010 Render inline code without a fill | A | DONE | [watchtower/tasks/TASK-010-unfilled-inline-code.md](watchtower/tasks/TASK-010-unfilled-inline-code.md) | TASK-009 | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Biggest remaining readability win. Also kills the wrapped-path fragments. |
| 11 | TASK-011 Show the On This Page rail in the Response tab | B | DONE | [watchtower/tasks/TASK-011-response-outline-rail.md](watchtower/tasks/TASK-011-response-outline-rail.md) | TASK-009 | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Uses the 333 points of dead space beside the answer. |
| 12 | TASK-012 Quiet the response header controls | B | DONE | [watchtower/tasks/TASK-012-quiet-response-header.md](watchtower/tasks/TASK-012-quiet-response-header.md) | TASK-009 | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Style only. Five solid accent buttons become ghost. |
| 13 | TASK-013 Parse long front matter with quoted keys | A | DONE | [watchtower/tasks/TASK-013-front-matter-parse.md](watchtower/tasks/TASK-013-front-matter-parse.md) | - | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | User-reported break, not planned. Two limits, either one alone breaks the block. |
| 14 | TASK-014 Size the front matter key column from its content | A | DONE | [watchtower/tasks/TASK-014-front-matter-key-column.md](watchtower/tasks/TASK-014-front-matter-key-column.md) | TASK-013 | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Follow-up to the reported break. Fixed share wrapped deep dotted keys. |

TASK Status labels: TODO, IN PROGRESS, BLOCKED, DONE.

## Groups

- Group `docs` writes [DESIGN.md](DESIGN.md) only.
- Group `A` writes
  [app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift](app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift).
  The four TASKs share that file, so they are one write group.
- Group `B` writes
  [app/Atelier/Sources/Atelier/Agent/AgentResponsesView.swift](app/Atelier/Sources/Atelier/Agent/AgentResponsesView.swift).
- Group `A` and Group `B` both write
  [app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift](app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift).
  That is a write conflict. Never run the two groups in parallel.

## Plan Verify

- `swift build --package-path app/Atelier` -> build succeeds with no new warnings.
- `swift test --package-path app/Atelier` -> all tests pass.
- `app/Atelier/.build/debug/Atelier --selftest` -> `SELFTEST: ALL PASS`.
- `rg -n "lineSpacing: AtelierMetrics" app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift` -> no match, so no absolute line spacing remains in a paragraph style.
- `app/Atelier/scripts/build_and_run.sh run` -> the app builds, signs, installs, and launches.
- `ps -p <PID> -o %cpu=` after the app settles -> idle CPU stays between 0.2 and 2 percent.

## Handoff

- Round one, TASK-001 through TASK-008, is DONE. Plan Verify passed in full: no absolute line
  spacing remains, build complete, 438 tests in 41 suites passed, `SELFTEST: ALL PASS`, and the app
  ran with settled `cpuPercent` 0.0118 and no new crash report.
- TASK-008 drove the on-screen pass with the native capture path, not a plugin. It found one
  regression and four defects. The regression, a 21.5 point question overhang, reopened TASK-006 and
  is fixed and re-measured at 1.5 points.
- Round two, TASK-009 through TASK-012, is DONE. Inline code lost its fill, the response panel gained
  the shared On This Page rail, and the header controls went quiet.
- Plan Verify passed after round two: no absolute line spacing remains, build complete, 438 tests in
  41 suites passed, `SELFTEST: ALL PASS`, settled `cpuPercent` 0.0065, empty verdict list, and no
  Atelier crash report.
- Each round-two change was proved on screen by pixel sample, not by assertion alone. Inline code
  fill went from `#D5D0C9` to `#F8F7F4`, the page color. Header control fill went from `#AC4628` to
  `#E7E3DD`, the header chrome color.
- Three planned risks did not exist. TASK-007 needed no cross-card wiring, because the response panel
  renders one card at a time. TASK-006 needed no font-scale change, because the question already
  scales with the transcript. TASK-010 needed no table-cell work, because removing the fill removed
  the thing that fragmented.
- TASK-013 was not planned. The user reported that front matter rendered as a divider plus one
  run-on paragraph. Two independent limits caused it, and either alone was enough: a 64-line scan
  bound against a 186-line block, and a key charset check that ran before unquoting, which rejected
  the quoted numeric keys YAML requires.
- Next action: nothing is blocked. Archive the plan when ready, or take an open finding below.
- Open finding, no TASK yet: JetBrains Mono contextual ligatures apply to inline code in prose, so a
  literal `<!--` renders as a left arrow and `-->` as a right arrow. That misrepresents quoted source
  inside a sentence. [DESIGN.md](DESIGN.md) asks for ligatures in the editor and terminal and says
  nothing about inline runs in prose.
- Open finding, no TASK yet: a long dotted front-matter key wraps mid-word in the key column, so
  `colors.surface.surface-hover` breaks as `colors.surface.surface-ho` and `ver`.
- Open finding, no TASK yet: a front-matter value containing backticks shows them literally. That is
  faithful to YAML but reads oddly beside inline code everywhere else.
- Lesson from both rounds: build and test proved nothing about readability. Every defect in this plan
  came from looking at the running app and sampling pixels, including a regression that a passing
  test suite had already signed off.

## Archive

- Archived: 2026-07-31 -> watchtower/archive/20260731-markdown-reading-pass/
- 2026-07-31: 20260731-unify-markdown-renderers
- 2026-07-30: 20260730-response-panel-question-and-refresh
- 2026-07-28: 20260728-transcript-refresh-skip-unchanged
- 2026-07-28: 20260728-quick-open-external-paths-and-idle-cpu
- 2026-07-26: 20260726-editorial-markdown-preview-enhancements
