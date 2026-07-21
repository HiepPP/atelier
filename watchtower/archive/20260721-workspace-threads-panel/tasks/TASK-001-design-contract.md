# TASK-001 Update DESIGN.md contract

Group: A (design contract must change before any code)

## Brief

Goal: Update [DESIGN.md](DESIGN.md) so nested thread rows are part of each workspace group before code lands. There is no separate Threads tab.

Change: Workspace panel lists flat workspace rows -> each workspace becomes a group with its header and nested thread rows.

How:

- Read the Workspace Rail and Sidebar sections in [DESIGN.md](DESIGN.md).
- Keep the Sidebar contract limited to Explorer and Git.
- Define each workspace as one group with a workspace header and nested thread rows. Do not add a Threads tab.
- Add a Threads subsection for nested rows. State that it lists terminals that run or ran an agent, grouped across all live workspaces. State the empty group text "No threads yet".
- Define the row: a status dot (running or done), the agent name, and a trailing relative time. Keep `rowHeight` at 28, pointer cursor, and the shared selection pill. Row geometry stays stable across states, per the interaction rules.
- Define detection: read the foreground process of each terminal pty and match an agent name list. State that Atelier does not inject shell integration, so detection must not depend on OSC 133.
- Define lifecycle: a thread stays while its terminal is open, moves from running to done, and disappears when the terminal closes. There is no history store.
- Define performance: refresh runs only while the Workspace panel is mounted and the app is active.
- Define interaction: clicking a thread activates its workspace when needed, then focuses the matching terminal tab.
- Update the Document Status `Updated` field to 2026-07-21. Do not change the baseline commit line.

Files:

- [DESIGN.md](DESIGN.md) (extend the Workspace Rail section with nested thread-row contract; keep Sidebar limited to Explorer and Git; update the Updated date)

Expected result:

- The Workspace Rail section defines workspace groups with nested thread rows and no Threads tab.
- The Sidebar section still names only Explorer and Git.
- A Threads subsection defines scope, grouping, row content, detection, lifecycle, performance gating, and click behavior.
- The contract matches the plan in [watchtower/CONTEXT.md](watchtower/CONTEXT.md).

## Verify

- Read the Workspace Rail section in [DESIGN.md](DESIGN.md) -> it defines workspace groups with nested thread rows and includes the Threads subsection.
- Read the Sidebar section -> it remains limited to Explorer and Git.
- `rg -n "Threads" DESIGN.md` -> shows the new contract text.
- No code file changed in this TASK -> `git status --short` lists only DESIGN.md.
