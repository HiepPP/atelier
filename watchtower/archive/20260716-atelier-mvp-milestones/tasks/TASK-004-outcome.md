# TASK-004 Outcome

## Outcome

Status: BLOCKED

Changed:
- Added cancellable background Git commands with concurrent output draining.
- Added porcelain v2 parsing for ordinary, renamed, unmerged, and untracked records.
- Added Changes as the default panel, pinned unified diffs, and FSEvents invalidation.

Contract:
- Git uses `/usr/bin/git` with argument arrays and path separators.
- Request IDs reject stale status and diff results.
- FSEvents debounces invalidation, then Git status remains the source of truth.

Verified:
- `cd app/Atelier && swift build` -> build complete.
- `cd app/Atelier && swift run Atelier --selftest` -> staged, unstaged, untracked, rename, and conflict parser cases passed.
- Git Process selftest -> `status --porcelain=v2 -z` completed.
- Native executable launch -> process stayed alive; live edit and diff selection were not automated.
- Resumed Computer Use check against the signed app path and bundle ID -> failed before changes or diff interaction.

Blocked:
- Signed `.app` bundle is ready, but Computer Use authentication blocks external-edit and diff checks.
