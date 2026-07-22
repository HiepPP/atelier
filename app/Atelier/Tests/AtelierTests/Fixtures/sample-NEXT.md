# NEXT

## Current Active Plan

Title: Gacha Size Quiz
Slug: 20260620-gacha-size-quiz
Status: ARCHIVED
Updated: 2026-06-21

## Tracker

| Order | TASK | Group | Status | Spec | Deps | Context | Notes |
|---:|---|---|---|---|---|---|---|
| 1 | TASK-001 Build quiz state and markup shell | standalone | DONE | watchtower/tasks/TASK-001-build-quiz-state-and-markup-shell.md | - | CONTEXT.md | Done. Shell refactored to 3-zone gacha. Scoring/mascot/affiliate preserved. |
| 2 | TASK-002 Build gacha visual shell | standalone | DONE | watchtower/tasks/TASK-002-build-gacha-visual-shell.md | TASK-001 | CONTEXT.md | Done. Red cabinet, marquee, light rails, knob, tray, dense CSS capsules match target closer. |
| 3 | TASK-003 Add optional chamber enhancement | standalone | DONE | watchtower/tasks/TASK-003-add-optional-three-chamber.md | TASK-002 | CONTEXT.md | Done. CSS chamber source of truth. WebGL gated off until it can match shape. |
| 4 | TASK-004 Integrate responsive flow and QA | standalone | BLOCKED | watchtower/tasks/TASK-004-integrate-responsive-flow-and-qa.md | TASK-003 | CONTEXT.md | Visual/responsive pass. Blocked by pre-existing audit product URL placeholders. |

## Plan Verify

- `git diff --check`
- `pnpm check`
- `pnpm build`
- `pnpm audit:launch`
- Manual responsive check: desktop >=1024, tablet 768-1023, mobile <768, small mobile <480.
- Manual motion check: normal motion, `prefers-reduced-motion`, CSS chamber fallback.
- Screenshot evidence saved under `.playwright-mcp/` for desktop and mobile.

## Handoff

Visual mismatch fixed on 2026-06-20. Render now uses red cabinet, dark marquee, side light rails, rounded glass chamber, dense CSS capsules, white center size ball, coin slot, knob, result checklist, product suggestion, and mobile sticky CTA.

Passed: `git diff --check`, `pnpm check`, `pnpm build`. Result click works. Affiliate result link keeps `rel="sponsored nofollow noopener noreferrer"` and data attrs after click.

Blocked gate: `pnpm audit:launch` still fails on pre-existing product affiliate URL placeholders (`https://shopee.vn`) in product JSON. Quiz fix did not touch product JSON.

Evidence:
- `.playwright-mcp/gacha-image-to-code-desktop-1440-final.png`
- `.playwright-mcp/gacha-image-to-code-tablet-900-final.png`
- `.playwright-mcp/gacha-image-to-code-mobile-390-final.png`
- `.playwright-mcp/gacha-fix-result-clicked-desktop.png`

Next action: fix existing product affiliate URLs or approve separate audit-gate exception before commit.

## Archive

- Archived: 2026-06-21 -> watchtower/archive/20260620-gacha-size-quiz/
- Existing archive: watchtower/archive/20260619-bo-suu-tap-game-console-redesign/
- Existing archive: watchtower/archive/20260619-bo-suu-tap-master-page/
