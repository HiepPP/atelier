# Session Review

Plan: Quick Open external paths and idle CPU burst
Slug: 20260728-quick-open-external-paths-and-idle-cpu
Archived: 2026-07-28

## TASK-001 Quick Open external paths

Plan vs shipped: match on behavior, drift on the file list.

- The spec listed `AtelierPaletteView.swift` as a file to change. It was not changed. The existing
  `fileRow` already renders `candidate.relativePath` in the required monospaced style, and the
  external candidate carries its absolute path in that field. The builder judged a pass-through
  property to be single-use indirection and skipped it. That call was correct.
- The spec did not list `WorkspaceSession.swift`, but the change needed it to pass `rootURL` into
  the palette model. The spec's file list was incomplete.
- Mistake: the spec guessed the file list from the symptom instead of from the data flow.
- Fix for next time: when a TASK needs a new value inside a model, trace where that value is owned
  and list the owner in `Files:`.

Verify was run in full and passed, including a clean-tree control run that proved the failing tests
were pre-existing flakes.

## TASK-002 Idle CPU burst investigation

Plan vs shipped: the goal was met, the acceptance bar was not, and the named suspects were wrong.

- The spec listed `AgentResponses.swift`, `GitService.swift`, and `Agent/Sidecar/` as suspects. The
  real owners were `AgentResponses.swift` and `AtelierPaletteModel.swift`. The palette was never
  listed as a suspect at all.
- Two separate defects shared one symptom. The first pass fixed the palette index walk and cut the
  peak from 71 to 53 percent, which looked like progress but was not the dominant cost. Only a
  second sample, taken inside a burst on a quiet machine, named the transcript watcher.
- Mistake: the first sample was read too early and its conclusion was too weak. The evidence in the
  spec said "none confirmed as the owner" but the investigation still started from that list.
- Fix for next time: sample inside the burst before naming any suspect, and expect more than one
  owner when a symptom survives the first fix.
- Acceptance bar not met. The spec required all five highest values at or below 2 percent. The
  final window gave 7.1, 6.7, 3.1, 2.8, 2.5 with a median of 0.7. This was recorded as a residual
  with numbers rather than reported as a pass.

## Plan Level

- Wrong grouping for the fan-out. The two TASKs were grouped as independent because their spec file
  lists did not overlap. The real fix for TASK-002 landed in `AtelierPaletteModel.swift`, which was
  TASK-001's file. The two builders collided, and the TASK-002 builder reverted a TASK-001 edit
  before restoring it from a backup. Nothing was lost, but the risk was real.
  - Fix for next time: group by the files a fix is likely to touch, not by the files the symptom
    points at. When a performance TASK has an unknown owner, treat it as overlapping every group.
- Verification method conflicted with parallel execution. TASK-002 required a 5-minute idle window
  while TASK-001's builder was running builds and launching the app in the same repo. The measured
  window was not idle, and the agent burned several retries before the main session stopped it.
  - Fix for next time: never run a machine-level performance measurement in parallel with another
    builder. Sequence that TASK last, or reserve a quiet window for it.
- An earlier claim in the session said the CPU burst was pre-existing and unrelated to the Markdown
  work. The attribution was right and was proven with a stashed control run. The claim still stopped
  short of root cause, and the burst turned out to be a real fixable defect.

## Lessons

- One file-tree revision fans out to every consumer. A consumer must not do expensive work on that
  signal while its UI is closed.
- A running agent writes its own transcript continuously, so its watcher emits a steady stream, not
  occasional events. Any per-event refresh becomes a hot loop.
- Measure idle CPU across a full 5-minute window. A 12-second window misses the burst and reports a
  false pass. That exact error produced a wrong "no regression" claim earlier in the session.
- A fix that lowers a number is not proof that the owner was found. Re-sample after each fix.
