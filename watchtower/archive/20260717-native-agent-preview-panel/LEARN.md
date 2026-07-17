# Learn 20260717-native-agent-preview-panel

## Summary

Discrepancy: 3 found. The preview panel shipped, but two plan details and the final worktree scope differed.

## Per TASK

- TASK-001: match.
- TASK-002: The plan removed the Responses center tab. The shipped panel keeps `WorkspaceSession.openResponses()` as a preview action. Mistake: the verify search treated the method name as the old behavior. Fix: search for the `.responses` tab case and `TerminalTabsModel.openResponses` instead.
- TASK-003: match.
- TASK-004: The plan listed `viewer.html`, but the shipped cache and card changes did not edit it. Mistake: the file list assumed the existing resource needed a change. Fix: inspect bundled rendering styles before naming the resource as a required target.

## Plan-Level

- Git diff tabs were added after this plan finished. This unrelated feature shared the final worktree and commit scope. Archive and commit a completed plan before starting another feature.

## Lessons

- Verify behavior through precise symbols, not broad method names.
- Confirm an existing resource needs edits before listing it as required.
- Close completed plan work before adding an unrelated feature to the same worktree.
