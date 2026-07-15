# TASK-005 Outcome

## Outcome

Status: BLOCKED

Changed:
- Added stage, unstage, discard, commit, and local branch switching.
- Added discard confirmation and empty-message commit blocking.
- Added rename-aware unstage using both current and original pathspecs.
- Added unborn-repository unstage fallback through `git rm --cached -f`.

Contract:
- File paths use `--` before path arguments.
- Unstaging a rename resets both sides without changing the worktree rename.
- Unstaging in an unborn repository preserves modified worktree content.
- Every action refreshes Git truth after success.
- Branch switching accepts only names returned by the local branch list.

Verified:
- `cd app/Atelier && swift build` -> build complete.
- `cd app/Atelier && swift run Atelier --selftest` -> `SELFTEST: ALL PASS`.
- Selftest proved staged rename unstage clears both index paths and preserves the renamed worktree file.
- Selftest proved unborn modified-content unstage clears the index and preserves newer worktree content.
- Native executable launch -> process stayed alive; stage, commit, and branch GUI flows were not automated.
- Git log proof was not run because no disposable GUI workspace was opened.
- Resumed Computer Use check against the signed app path and bundle ID -> failed before stage or commit interaction.

Blocked:
- Signed `.app` bundle is ready, but Computer Use authentication blocks stage, commit, branch, and `git log -1` GUI checks.
