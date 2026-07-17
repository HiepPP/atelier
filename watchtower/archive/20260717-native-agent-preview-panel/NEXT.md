# NEXT

## Current Active Plan

- Title: Native Agent Preview Panel
- Slug: 20260717-native-agent-preview-panel
- Status: ARCHIVED
- Updated: 2026-07-18

## Tracker

One row per TASK. Group ties together items that ship as one transaction.

| Order | TASK | Group | Status | Spec | Deps | Context | Notes |
|-------|------|-------|--------|------|------|---------|-------|
| 1 | TASK-001 Stabilize transcript sessions | A | DONE | [watchtower/tasks/TASK-001-stabilize-transcript-sessions.md](watchtower/tasks/TASK-001-stabilize-transcript-sessions.md) | - | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Deterministic provider-scoped sessions, deduplication, selection, and unread state verified. |
| 2 | TASK-002 Build the adaptive preview panel | B | DONE | [watchtower/tasks/TASK-002-build-adaptive-preview-panel.md](watchtower/tasks/TASK-002-build-adaptive-preview-panel.md) | TASK-001 | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Docked and overlay layouts preserve the live SwiftTerm TUI and restore focus. |
| 3 | TASK-003 Polish Markdown response cards | B | DONE | [watchtower/tasks/TASK-003-polish-markdown-response-cards.md](watchtower/tasks/TASK-003-polish-markdown-response-cards.md) | TASK-002 | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Native Markdown, code, tables, copy, and pending-response behavior verified. |
| 4 | TASK-004 Stabilize Mermaid preview and launch | C | DONE | [watchtower/tasks/TASK-004-stabilize-mermaid-preview-and-launch.md](watchtower/tasks/TASK-004-stabilize-mermaid-preview-and-launch.md) | TASK-003 | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Cached responsive diagrams and selectable error fallback passed automated and native UI checks. |

TASK Status labels: TODO, IN PROGRESS, BLOCKED, DONE.
Plan-level Status header: ACTIVE while any row is open, DONE when all rows DONE, ARCHIVED after archive.

## Plan Verify

- `swift build --package-path app/Atelier` completes without errors.
- `swift test --package-path app/Atelier` passes all deterministic tests.
- `app/Atelier/.build/debug/Atelier --selftest` passes all packaged checks.
- `rg -n "Mermaid|AgentResponse|AgentPreview" app/Atelier/Sources/Atelier/Terminal/TerminalController.swift` returns no matches.
- A Codex TUI and a Claude TUI stay interactive while the preview panel opens, closes, and resizes.
- Two concurrent sessions remain separate and receive no duplicate response cards.
- The panel passes a 1000 x 700 narrow check and a 1600 x 1000 wide check.
- Invalid Mermaid source shows selectable source without a blank or black render area.
- `app/Atelier/scripts/build_and_run.sh run` builds, signs, installs, and launches Atelier.

## Handoff

- Next action: Review and commit the completed native preview panel changes.

## Archive

- Archived: 2026-07-18 -> watchtower/archive/20260717-native-agent-preview-panel/
