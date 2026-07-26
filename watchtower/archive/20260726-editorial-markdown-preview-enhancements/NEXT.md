# NEXT

## Current Active Plan

- Title: Editorial Markdown Preview Enhancements
- Slug: 20260726-editorial-markdown-preview-enhancements
- Status: ARCHIVED
- Updated: 2026-07-26

## Tracker

| Order | TASK | Group | Status | Spec | Deps | Context | Notes |
|-------|------|-------|--------|------|------|---------|-------|
| 1 | TASK-001 GitHub callout cards | standalone | DONE | [watchtower/tasks/TASK-001-github-callout-cards.md](watchtower/tasks/TASK-001-github-callout-cards.md) | - | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Focused verification passed. |
| 2 | TASK-002 Nested list depth | standalone | DONE | [watchtower/tasks/TASK-002-nested-list-depth.md](watchtower/tasks/TASK-002-nested-list-depth.md) | - | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Focused verification passed. |
| 3 | TASK-003 Table alignment | standalone | DONE | [watchtower/tasks/TASK-003-table-alignment.md](watchtower/tasks/TASK-003-table-alignment.md) | - | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Focused verification passed. |
| 4 | TASK-004 Baseline rhythm | standalone | DONE | [watchtower/tasks/TASK-004-baseline-rhythm.md](watchtower/tasks/TASK-004-baseline-rhythm.md) | - | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Focused verification passed. |
| 5 | TASK-005 Image figures | standalone | DONE | [watchtower/tasks/TASK-005-image-figures.md](watchtower/tasks/TASK-005-image-figures.md) | - | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Focused verification passed. |
| 6 | TASK-006 Code line numbers | standalone | DONE | [watchtower/tasks/TASK-006-code-line-numbers.md](watchtower/tasks/TASK-006-code-line-numbers.md) | - | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Focused verification passed. |
| 7 | TASK-007 Optical quote and list markers | standalone | DONE | [watchtower/tasks/TASK-007-optical-quote-and-list-markers.md](watchtower/tasks/TASK-007-optical-quote-and-list-markers.md) | - | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Focused verification passed. |
| 8 | TASK-008 Front matter masthead | standalone | DONE | [watchtower/tasks/TASK-008-front-matter-masthead.md](watchtower/tasks/TASK-008-front-matter-masthead.md) | - | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Focused verification passed. |
| 9 | TASK-009 Footnotes | standalone | DONE | [watchtower/tasks/TASK-009-footnotes.md](watchtower/tasks/TASK-009-footnotes.md) | - | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Focused verification passed. |
| 10 | TASK-010 Link and outline progress | standalone | DONE | [watchtower/tasks/TASK-010-link-and-outline-progress.md](watchtower/tasks/TASK-010-link-and-outline-progress.md) | - | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Focused verification passed. |

## Plan Verify

- `swift build --package-path app/Atelier` -> the package builds without warnings from changed code.
- `swift test --package-path app/Atelier --quiet` -> all tests pass.
- `app/Atelier/.build/debug/Atelier --selftest` -> reports `SELFTEST: ALL PASS`.
- `app/Atelier/scripts/build_and_run.sh run` -> builds, signs, installs, and opens Atelier once.
- Native path 1 at full window size -> one fixture proves callouts, nested lists, tables, rhythm, quotes, masthead, and footnotes.
- Native path 2 at full window size -> local image stays stable, code numbers display, and `Cmd-C` excludes line numbers.
- Native path 3 at full window size -> links strengthen on hover and the outline progress hairline follows passive scroll without animation.
- `app/Atelier/scripts/atelier-doctor status --json` -> runtime status is healthy after the paths.
- `ps -p <PID> -o %cpu=` -> idle CPU remains within 0.2-2 percent.
- `git diff --check` -> no whitespace errors.

## Handoff

- Implementation and focused TASK verification are complete.
- `swift build --package-path app/Atelier` passed.
- Full `swift test --package-path app/Atelier --quiet` completed all 282 tests. The first run exposed the known 5 ms cancellation timing flake; the exact rerun passed.
- `app/Atelier/.build/debug/Atelier --selftest` reported `SELFTEST: ALL PASS`.
- `app/Atelier/scripts/build_and_run.sh run` built, signed, installed, and opened Atelier.
- Native path 1 passed at full window size. One fixture showed callouts, nested list markers, aligned tables, rhythm, the pull quote, the front-matter masthead, and numbered Notes.
- Native path 2 passed at full window size. The local image rendered at stable bounds, code lines showed numbers, and `Cmd-C` produced only the three source lines.
- Native path 2 regression follow-up passed at full window size. Line numbers `1` through `3` stayed fully inside the code-card gutter, and native `Cmd-C` again returned only the three source lines.
- Native path 2 glyph follow-up passed at full window size. Line numbers `1`, `2`, and `3` rendered upright in the flipped native text context; `Cmd-C` still returned only source text.
- Native path 3 progress passed at full window size. Passive scroll moved the native value from `0.5851821360` to `0.8865656793`, selected `Footnotes`, and extended the outline hairline without a visible transition.
- Native path 3 hover passed at the full `1710 x 1010` window size. Computer Use before/after captures showed the native link underline strengthen, and a cursor-inclusive capture showed the pointing-hand cursor. A Quartz `CGEvent` pointer move supplied coordinates because the bundled Computer Use coordinate injector still returned `noWindowsAvailable`.
- The Git hang is fixed by marking every Git pipe endpoint `FD_CLOEXEC`. Concurrent child launches can no longer retain another command's writer and prevent EOF.
- Runtime doctor reported `healthy` for PID `19418`; idle CPU was `0.5%`.
- Regression follow-up runtime doctor reported `healthy` for PID `41124`; three idle CPU reads were `0.8%`.
- Glyph follow-up runtime doctor reported `healthy` for PID `48773`; three idle CPU reads were `0.1%`.
- `git diff --check` passed.
- Every Plan Verify gate passed. This plan is `DONE`.

## Archive

- Existing plans remain under [watchtower/archive/](watchtower/archive/).
- Archived: 2026-07-26 -> watchtower/archive/20260726-editorial-markdown-preview-enhancements/
