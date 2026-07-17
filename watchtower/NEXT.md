# NEXT

## Current Active Plan

- Title: Gemma 4 Read-Only Agent
- Slug: 20260717-gemma4-read-only-agent
- Status: ACTIVE
- Updated: 2026-07-17

## Tracker

One row per TASK. Group ties together items that ship as one transaction.

| Order | TASK | Group | Status | Spec | Deps | Context | Notes |
|-------|------|-------|--------|------|------|---------|-------|
| 1 | TASK-001 Add Ollama chat transport | A | DONE | [watchtower/tasks/TASK-001-add-ollama-chat-transport.md](watchtower/tasks/TASK-001-add-ollama-chat-transport.md) | - | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Streaming, remote errors, privacy, and cancellation verified. |
| 2 | TASK-002 Add safe workspace tools | B | DONE | [watchtower/tasks/TASK-002-add-safe-workspace-tools.md](watchtower/tasks/TASK-002-add-safe-workspace-tools.md) | - | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Read-only bounds, containment, secrets, Git, and cancellation verified. |
| 3 | TASK-003 Build the Gemma agent loop | C | DONE | [watchtower/tasks/TASK-003-build-gemma-agent-loop.md](watchtower/tasks/TASK-003-build-gemma-agent-loop.md) | TASK-001, TASK-002 | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Atomic history, tool limits, state, privacy, and cleanup verified. |
| 4 | TASK-004 Add the native Gemma tab | C | BLOCKED | [watchtower/tasks/TASK-004-add-native-gemma-tab.md](watchtower/tasks/TASK-004-add-native-gemma-tab.md) | TASK-003 | [watchtower/CONTEXT.md](watchtower/CONTEXT.md) | Code and tests pass. Native visual and focus checks need manual verification. |

TASK Status labels: TODO, IN PROGRESS, BLOCKED, DONE.
Plan-level Status header: ACTIVE while any row is open, DONE when all rows DONE, ARCHIVED after archive.

## Plan Verify

- `swift build --package-path app/Atelier`
- `swift test --package-path app/Atelier`
- `app/Atelier/.build/debug/Atelier --selftest`
- Sign in with `ollama signin`, then confirm `gemma4:cloud` can inspect a test workspace.
- Confirm an outside-workspace path request is rejected without reading the file.
- Confirm stopping the run or closing the workspace cancels active network and tool work.

## Handoff

- Next action: Manually verify the Gemma tab at narrow and wide sizes, then run `$watchtower verify`.

## Archive

- None.
