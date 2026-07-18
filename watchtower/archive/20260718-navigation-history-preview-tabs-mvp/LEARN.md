# Learn 20260718-navigation-history-preview-tabs-mvp

## Summary

Discrepancy: 1 found. The MVP shipped, then preview crash hardening expanded the final UI work.

## Per TASK

- TASK-001: match. Preview replacement, promotion, cleanup, and recent-file rules shipped as planned.
- TASK-002: match. Session-only Back, Forward, and closed-file history shipped with deterministic tests.
- TASK-003: match. Explorer owns preview, while double-click, edit, and Cmd+P keep permanent behavior.
- TASK-004: actions and native chrome shipped. Crash hardening also changed panel state and responder restore safety. Mistake: the plan missed repeated panel transition stress. Fix: add AppKit log checks to native verification.

## Plan-Level

- The crash fix added `HSplitView`, atomic panel transitions, and a responder ownership guard. These files were outside the original TASK-004 list.
- TASK-004 outcome recorded 103 tests. Final verification passed 104 tests after the panel transition test was added.

## Lessons

- Stress preview clicks across sidebar, inspector, and window size transitions.
- Treat AppKit constraint-loop warnings as failures, even when the app stays open.
- Restore a saved responder only when it still belongs to the target window.
