# TASK-004 M3 git changes list and unified diff

Group: M3 (git observation milestone, ships on its own)

## Brief

Goal: Show git changes for the workspace and a read-only unified diff. Auto-refresh on file changes.

Change: no git view -> a changes list plus a unified diff, updated after edits.

How:

- Add GitService that runs git through Process with an argument array. No shell strings.
- Run git status --porcelain=v2 -z, git diff, git diff --cached, git branch --show-current.
- Each request supports cancellation. Guard results by workspace so stale output cannot overwrite new state.
- Add a ChangesView that splits staged, unstaged, and untracked files.
- Add a read-only unified DiffView from git diff output, using TextKit 2.
- Add an FSEvents watcher for the workspace. Debounce events, then run git status. See [PLAN.md](PLAN.md) State Transitions.
- If a diff is open and the file changes, show a reload flag. Do not swap the content while the user reads.

Files:

- [app/Atelier/Sources/Atelier/GitService.swift](app/Atelier/Sources/Atelier/GitService.swift) (Process based git)
- [app/Atelier/Sources/Atelier/GitStatus.swift](app/Atelier/Sources/Atelier/GitStatus.swift) (parse porcelain v2)
- [app/Atelier/Sources/Atelier/ChangesView.swift](app/Atelier/Sources/Atelier/ChangesView.swift) (staged, unstaged, untracked)
- [app/Atelier/Sources/Atelier/DiffView.swift](app/Atelier/Sources/Atelier/DiffView.swift) (read-only unified diff)
- [app/Atelier/Sources/Atelier/FileWatcher.swift](app/Atelier/Sources/Atelier/FileWatcher.swift) (FSEvents, debounce)
- [app/Atelier/Sources/Atelier/ContentView.swift](app/Atelier/Sources/Atelier/ContentView.swift) (changes tab as default panel)

Expected result:

- Changes is the default panel and shows correct git state.
- Editing a file outside the app updates the changes list after a short debounce.
- Selecting a changed file shows its unified diff.
- The branch name shows in the UI.

## Verify

- cd app/Atelier && swift build -> ok (build complete).
- Add a GitStatus parser selftest with sample porcelain v2 output -> correct staged, unstaged, untracked split.
- Launch app on a repo, edit a file, watch the change appear, open its diff.
