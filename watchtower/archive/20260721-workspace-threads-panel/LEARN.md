# Learn 20260721-workspace-threads-panel

## Summary

Discrepancy: minor. The plan shipped as specified. The UI was refined beyond the spec after user pixel review.

## Per TASK

- TASK-001: match. DESIGN.md gained the Threads contract. It later moved from a Threads tab to nested rows, then to collapsible recessed groups with a trailing chevron.
- TASK-002: match. Agent detection reads the terminal pty foreground process and matches argv against the agent name list. No OSC 133 dependency.
- TASK-003: match. ThreadsPanelModel derives groups from snapshots, keeps a run-state map, and diffs before assigning groups.
- TASK-004: shipped, with change. The plan first placed threads in a sidebar Threads tab, then the implement run moved them to nested rows under each workspace header in the rail. A follow-up then refined the visual to collapsible recessed groups with a trailing disclosure chevron and a collapsed running-count badge, after the user called the first render ugly.

## Plan-Level

- The target surface changed twice: sidebar Threads tab -> nested rail rows -> collapsible recessed groups. The final design lives in DESIGN.md under Workspace Rail / Threads.
- The recessed-group visual polish happened after the plan was marked DONE, outside the tracked tasks.

## Lessons

- For a visible UI feature, add a dedicated visual-polish task and review real pixels with the user early. Text mockups did not settle the look; rendered screenshots did.
- Foreground-process detection is enough for agent status. Do not depend on OSC 133, since Atelier does not inject shell integration.
- Gate the refresh loop to the visible, active panel with `.task` so idle CPU stays flat.
