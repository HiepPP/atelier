# TASK-001 Outcome

## Status

DONE

## Changed

- `DESIGN.md`
  - Architecture tree: inspector node now reads "Inspector: Gemma sidecar assistant".
  - Replaced the static-metadata inspector contract with a new "### Gemma Sidecar
    Assistant" section under Surface Rules.
  - Documented layout (compact header; feature cards; quick-action row; streaming
    response area; prompt field with clear), the empty state, the separate sidecar
    runtime, and prompt-context injection (system prompt unchanged).
  - Added a quick-actions-per-tab-kind table: File (explain, summarize, find usages),
    Git diff (review, commit message), Terminal (explain last error, explain command),
    Editor selection (explain selection).
  - Documented the registry / feature-slot architecture under
    `app/Atelier/Sources/Atelier/Agent/Sidecar` and the five background features
    (Terminal Guardian, Claude Code Briefing, Session Journal, Intent Guard,
    Pre-commit Whisper), all stated read-only and cancellable.
  - Split the old "### Gemma and Agent Responses" heading into "### Gemma Sidecar
    Assistant" plus "### Agent Responses" (the overlay contract kept intact).

## Contract

DESIGN.md is updated BEFORE code. The sidecar section covers layout, quick actions
per tab kind, the registry/feature-slot architecture, and the five background
features with explicit read-only + cancellation rules. Tokens, spacing, and
accessibility guidance stay consistent with the existing design system (shared
panel-header contract, inspector spacing, one accent). No H4+; ASCII only.

## Verified

- DESIGN.md sidecar section reviewed against the checklist: layout, per-kind quick
  actions, registry, five features, read-only + cancellation - all present.
- `swift build --package-path app/Atelier` clean (docs change is non-breaking).
