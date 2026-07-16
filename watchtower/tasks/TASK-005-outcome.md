# TASK-005 Outcome

## Outcome

Status: BLOCKED

Changed:
- Built, installed, launched, and ad hoc signed the packaged app.
- Created a disposable Git workspace with modified, staged, and untracked files.
- Saved [narrow app proof](TASK-005-narrow.jpeg), [wide app proof](TASK-005-wide.jpeg), and [Open Folder proof](TASK-005-open-folder.jpeg).
- Saved clean and error card proof with TASK-004.

Contract:
- Verification did not mutate the disposable Git workspace.
- The branch control stayed a native menu. The commit control stayed disabled with an empty message.

Verified:
- `app/Atelier/script/build_and_run.sh --verify` -> app launched and stayed running.
- `codesign --verify --deep --strict --verbose=2 app/Atelier/dist/Atelier.app` -> valid on disk and satisfied its requirement.
- Final post-review package rebuild and codesign check -> passed after the primary-button fix.
- Computer Use wide capture -> three columns remained visible with no divider jump or material wash.
- Final Computer Use narrow capture -> 1002px outer width, matching the 1000px content minimum, kept all three columns visible.
- Computer Use -> Open Folder panel, New Terminal, disabled Commit, refresh control, and branch menu were present.
- Computer Use -> selected the disposable repository, ran unstage and stage, then cancelled the discard dialog.
- Computer Use -> clean repository and Git error cards rendered with Atelier palette styling.
- `git status --short` in `/tmp/atelier-visual.Ajtr5q` -> unchanged baseline: modified, staged, and untracked states remained.

Blocked:
- The current display caps the app screenshot at 1299px. A 1600px native window cannot fit.
- Reload, hover, pressed, and focus checks remain incomplete.
