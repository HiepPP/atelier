# TASK-001 Design contract for Gemma sidecar

Group: A (sidecar foundation ships as one slice)

## Brief

Goal: update [DESIGN.md](DESIGN.md) so the design contract describes the new Gemma sidecar before any code changes.

Change: inspector described as static metadata panel -> inspector described as context-aware Gemma assistant panel.

How:

- Read the current inspector section in [DESIGN.md](DESIGN.md).
- Describe the new sidecar layout: compact header (icon, title, status), quick action row, prompt field, streaming response area.
- Define quick actions per tab kind: file (explain, summarize, find usages), git diff (review, commit message), terminal (explain last error, explain command), editor selection (explain selection).
- Define background features at contract level: Terminal Guardian, Claude Code Briefing, Session Journal, Intent Guard, Pre-commit Whisper. State that all are read-only and cancellable.
- Keep tokens, spacing, and accessibility rules consistent with the existing design system.

Files:

- [DESIGN.md](DESIGN.md) (inspector section rewritten, new sidecar contract added)

Expected result:

- DESIGN.md describes the Gemma sidecar and its quick actions per tab kind.
- DESIGN.md lists the five background features with their read-only and cancellation rules.
- No code files change in this TASK.

## Verify

- Read [DESIGN.md](DESIGN.md) -> sidecar section covers layout, quick actions per tab kind, and the five background features.
- `git status --short` -> only DESIGN.md changed.
