# TASK-008 Outcome

## Outcome

Status: DONE

Method: no `computer-use` plugin is installed, so the pass used the native path recorded in memory.
`CGWindowListCopyWindowInfo` finds the window id, `screencapture -x -o -l <id>` captures it, and a
`CGEvent` scroll drives the surface. The user asked for visual verification, so screenshots are in
scope for this pass. Window 425418 at 1710x1010, PID 74298.

Verified, the CLI half:

- `app/Atelier/scripts/build_and_run.sh run` -> built, signed ad hoc, installed, launched.
- `app/Atelier/scripts/atelier-doctor status --json` -> `status healthy`, `workspace.active true`,
  settled `cpuPercent` 0.0118, `heartbeatPaused false`, empty verdict list.
- `ls -t ~/Library/Logs/DiagnosticReports/ | grep -i atelier` -> no Atelier crash report.

Acceptance points, Response tab:

1. FAIL. The question container and the answer column do not share a right edge. Measured from the
   capture: the question fill ends at 1132.5 points, the answer's table and heading rule end at
   1111.0 points. The 21.5 point overhang is the container's `spaceM` leading plus `spaceS` trailing
   padding, which sits outside the `transcriptMaxWidth` frame TASK-006 added. Owning TASK: TASK-006,
   reopened. The second half of the point passes: the question reads clearly larger than the answer
   body.
2. PARTIAL. Neutral is confirmed: the list marker samples `#7D7C7A` and the inline code fill samples
   `#D5D0C9`, with no terracotta anywhere in the body. The readability half fails. The fill is about
   15 percent darker than the `#F8F7F4` page and each run carries a 12 point kern on both sides, so a
   code-heavy paragraph reads as a mosaic of grey blocks rather than prose.
3. PASS. The pinned section bar shows the active heading and the accent progress line. It read
   `P2 - Pilot command-palette` on one answer and `Tóm tắt kế hoạch` on another, and tracked scroll.

Acceptance points, Markdown Preview:

1. PARTIAL PASS. H2 renders serif with the short accent lead and hairline rule, and separates
   clearly from the prose above it. H1, H3, and H4 were not on screen in the captured range.
2. NOT DRIVEN. No block quote appeared in the captured range.
3. NOT DRIVEN. Zoom 0.8 and 2.0 were not exercised.

New defects found by looking, none of which any test caught:

- Punctuation detaches from inline code. The 12 point reservation is added to the last character of
  every code run without checking the next character, so `tokens@^4.0.0` is followed by a wide gap
  and then a full stop. Same for a comma after `--primary`. A short word between two code runs, such
  as `in` or `and`, gets 12 points on each side and reads as its own box.
- A table cell that mixes inline code with prose fragments the chip. The path
  `tini-works/pvs-design-handoff` wraps into three separate chips with visible gaps. The DESIGN rule
  about one continuous chip only covers a cell that is pure code, so a mixed cell zebra-stripes.
- The response header carries five solid terracotta buttons. They are the loudest element on screen
  and sit directly above a body that TASK-005 just spent effort making quiet.
- The response overlay leaves about 333 points of empty space to the right of its 680 point column.
  Markdown Preview fills the same region with the On This Page rail.

Contract reconciliation:

- [DESIGN.md](DESIGN.md) was corrected during TASK-004, TASK-006, and TASK-007 where the code proved
  the contract wrong. No further correction is needed from this pass. The failing point is a code
  bug, not a contract error.
