# TASK-008 Drive the on-screen acceptance pass

Group: standalone
Class: risky

## Brief

Goal: Prove the reading pass on screen. Build and test results cannot judge typography.

Precondition: No `computer-use` plugin is installed on this machine, and repo rules forbid
screenshots unless the user asks for them. Every check below needs a human at the screen. An agent
must not mark this TASK DONE from CLI evidence alone.

Change: No code change unless a check fails. A failing check reopens the owning TASK.

How:

- Launch with `app/Atelier/scripts/build_and_run.sh run`.
- Run the checks at full window size. Add a second window size only if a check fails and resize is
  the suspected cause.
- Open one long agent answer in the Response tab. Open one long Markdown file in Preview.
- Reconcile [DESIGN.md](DESIGN.md) with what shipped. TASK-001 wrote the contract before the code
  existed, and the previous plan learned that a docs TASK written first usually needs a second pass.

Acceptance points, three per surface:

Response tab.

1. The question container and the answer column end at the same right edge, and the question reads
   larger than the answer body.
2. Inline code and list bullets read neutral. The answer no longer looks striped.
3. Scrolling shows the pinned section bar with the active heading and the progress line. It hides on
   an answer with fewer than two headings.

Markdown Preview.

1. Heading hierarchy is obvious from H1 down to H4, and H4 reads louder than the body text under it.
2. A block quote clearly separates from the paragraph above it.
3. Prose rhythm holds at both ends of the range. Check zoom 0.8 and zoom 2.0.

Files:

- [DESIGN.md](DESIGN.md): reconcile only if the shipped behavior differs from the contract.
- [watchtower/tasks/TASK-008-outcome.md](watchtower/tasks/TASK-008-outcome.md): record each point as
  PASS, FAIL, or NOT DRIVEN, with what was seen.

Expected result:

- Six acceptance points recorded with a real result each.
- Any FAIL names the owning TASK, which reopens.
- [DESIGN.md](DESIGN.md) and the shipped behavior agree.

## Verify

- `app/Atelier/scripts/build_and_run.sh run` -> the app builds, signs, installs, and launches.
- `app/Atelier/scripts/atelier-doctor status --json` -> `workspace.active` is true before any runtime
  reading is trusted. The build script signs ad hoc, which can drop the security-scoped bookmark.
- `app/Atelier/scripts/atelier-doctor status --json` -> settled `cpuPercent` stays between 0.2 and 2.
- `ls -t ~/Library/Logs/DiagnosticReports/ | head -5` -> no new Atelier crash report after the pass.
- Manual, needs a human at the screen: the six acceptance points above, each recorded in the outcome
  sidecar as PASS, FAIL, or NOT DRIVEN.
