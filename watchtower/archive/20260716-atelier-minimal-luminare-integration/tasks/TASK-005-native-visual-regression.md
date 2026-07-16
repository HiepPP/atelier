# TASK-005 Native visual regression pass

Group: D (full visual verification)

## Brief

Goal: Verify the minimal Luminare integration in the packaged native app. Record exact proof before promoting any visual task.

Change: compiled visual work -> verified native behavior and layout proof

How:

- Build and sign [app/Atelier/dist/Atelier.app](../../app/Atelier/dist/Atelier.app).
- Use a disposable Git workspace with clean, modified, staged, and untracked states.
- Inspect the app at 1000px and 1600px window widths.
- Exercise Open Folder, refresh, stage, unstage, discard cancel, commit disabled, new terminal, and branch menu flows.
- Confirm hover, pressed, focus, and disabled visuals remain readable.
- Confirm the native branch menu and discard dialog still use their original interaction model.
- Save screenshots and exact observations in the outcome sidecar.

Files:

- [app/Atelier/script/build_and_run.sh](../../app/Atelier/script/build_and_run.sh) (run existing verify mode)
- [watchtower/tasks/TASK-005-outcome.md](TASK-005-outcome.md) (record native proof)

Expected result:

- The three-column layout matches the current proportions at both widths.
- No clipping, overflow, divider jump, material wash, or palette drift appears.
- All tested actions keep their current behavior.
- Only tasks with complete proof are promoted to `DONE`.

## Verify

- `app/Atelier/script/build_and_run.sh --verify` -> signed app launches and stays running.
- `codesign --verify --deep --strict --verbose=2 app/Atelier/dist/Atelier.app` -> bundle passes validation.
- Computer Use at 1000px and 1600px -> three columns, buttons, status sections, menu, and dialog pass.
- `git status --short` in the disposable workspace after cancel-only checks -> no unexpected mutation.
