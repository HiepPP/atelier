# TASK-001 Outcome

## Outcome

Status: DONE

Changed:
- Updated the design date to 2026-07-21 without changing the baseline commit.
- Defined each workspace as one 44-point header with nested thread rows.
- Kept the sidebar limited to Explorer and Git. No Threads tab exists.
- Added thread scope, detection, lifecycle, refresh, and click contracts.

Contract:
- Thread rows sit directly below their workspace header in rail order.
- Detection reads each terminal pty foreground process and does not depend on OSC 133.
- Refresh runs only while the Workspace panel is mounted and the app is active.

Verified:
- Read the Workspace Rail section -> it defines nested threads and no Threads tab.
- Read the Sidebar section -> it still names only Explorer and Git.
- `rg -n "Threads" DESIGN.md` -> shows the nested thread contract.
- `git diff --check` -> passed.
