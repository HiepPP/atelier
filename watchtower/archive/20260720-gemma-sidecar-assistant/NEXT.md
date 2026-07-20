# NEXT

## Current Active Plan

- Title: Gemma Sidecar Assistant
- Slug: 20260720-gemma-sidecar-assistant
- Status: ARCHIVED
- Updated: 2026-07-20

## Tracker

One row per TASK. Group ties together items that ship as one transaction.

| Order | TASK | Group | Status | Spec | Deps | Context | Notes |
|-------|------|-------|--------|------|------|---------|-------|
| 1 | TASK-001 Design contract for Gemma sidecar | A | DONE | [watchtower/tasks/TASK-001-design-contract.md](watchtower/tasks/TASK-001-design-contract.md) | - | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | DESIGN.md first, per repo rule. |
| 2 | TASK-002 Sidecar Gemma panel with context injection | A | DONE | [watchtower/tasks/TASK-002-sidecar-gemma-panel.md](watchtower/tasks/TASK-002-sidecar-gemma-panel.md) | TASK-001 | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Replaces static inspector body. |
| 3 | TASK-003 read_terminal_output tool | B | DONE | [watchtower/tasks/TASK-003-read-terminal-output-tool.md](watchtower/tasks/TASK-003-read-terminal-output-tool.md) | TASK-002 | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Bounded scrollback, read-only. |
| 4 | TASK-004 Terminal quick actions | B | DONE | [watchtower/tasks/TASK-004-terminal-quick-actions.md](watchtower/tasks/TASK-004-terminal-quick-actions.md) | TASK-003 | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Explain error, explain command. |
| 5 | TASK-005 Terminal Guardian | B | DONE | [watchtower/tasks/TASK-005-terminal-guardian.md](watchtower/tasks/TASK-005-terminal-guardian.md) | TASK-004 | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Auto diagnosis on non-zero exit. |
| 6 | TASK-006 Claude Code briefing action | C | DONE | [watchtower/tasks/TASK-006-claude-code-briefing.md](watchtower/tasks/TASK-006-claude-code-briefing.md) | TASK-002 | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Gemma writes prompt, pastes to terminal. |
| 7 | TASK-007 Session Journal | D | DONE | [watchtower/tasks/TASK-007-session-journal.md](watchtower/tasks/TASK-007-session-journal.md) | TASK-003 | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Periodic session summary in sidecar. |
| 8 | TASK-008 Intent Guard | E | DONE | [watchtower/tasks/TASK-008-intent-guard.md](watchtower/tasks/TASK-008-intent-guard.md) | TASK-002 | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Warn when diff drifts from stated intent. |
| 9 | TASK-009 Pre-commit Whisper | F | DONE | [watchtower/tasks/TASK-009-precommit-whisper.md](watchtower/tasks/TASK-009-precommit-whisper.md) | TASK-002 | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Background scan of unstaged diff. |
| 10 | TASK-010 Unified feed redesign and larger type | standalone | DONE | [watchtower/tasks/TASK-010-unified-feed-redesign.md](watchtower/tasks/TASK-010-unified-feed-redesign.md) | TASK-002 | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | One feed, one input; type scale raised. |

TASK Status labels: TODO, IN PROGRESS, BLOCKED, DONE.
Plan-level Status header: ACTIVE while any row is open, DONE when all rows DONE, ARCHIVED after archive.

## Plan Verify

- `swift build --package-path app/Atelier` -> builds clean.
- `swift test --package-path app/Atelier` -> all tests pass.
- `app/Atelier/.build/debug/Atelier --selftest` -> self-test passes.
- `app/Atelier/scripts/build_and_run.sh run` -> app launches; sidecar shows Gemma panel for every tab kind.
- [DESIGN.md](DESIGN.md) matches shipped sidecar behavior.

## Handoff

- All 9 TASKs shipped via team fan-out (registry refactor): serial foundation (TASK-001 DESIGN + 002 sidecar/registry + 003 terminal tool + 6 feature stubs) then 6 concurrent feature builders (TASK-004..009), one integrated verify + one fix round.
- Plan Verify green: swift build clean; swift test 171 pass; --selftest ALL PASS; sidecar replaces the static inspector for every tab kind. Live GUI smoke via build_and_run.sh pending user run.
- TASK-010 shipped the one-feed, one-input redesign with a raised type scale; live GUI smoke done (screenshot: streamed answer, chips, single input).
- Next action: archive with watchtower archive.

## Archive

- Archived: 2026-07-20 -> watchtower/archive/20260720-gemma-sidecar-assistant/
