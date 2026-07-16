# TASK-005 M4 git basic operations

Group: M4 (git action milestone, ships on its own)

## Brief

Goal: Add basic git actions from the app. Stage, unstage, discard, commit, and switch branch.

Change: read-only git view -> stage, commit, and branch actions work from the app.

How:

- Extend GitService with git add, git restore --staged, git restore, git commit -m, git checkout.
- Add stage and unstage actions on rows in the changes list.
- Add discard with a clear confirm dialog, since it drops work.
- Add a commit box with a message field. Block commit when the message is empty.
- Show the current branch and allow switching to another local branch.
- Refresh the changes list after each action.

Files:

- [app/Atelier/Sources/Atelier/GitService.swift](app/Atelier/Sources/Atelier/GitService.swift) (add write commands)
- [app/Atelier/Sources/Atelier/ChangesView.swift](app/Atelier/Sources/Atelier/ChangesView.swift) (stage, unstage, discard, commit UI)
- [app/Atelier/Sources/Atelier/BranchControl.swift](app/Atelier/Sources/Atelier/BranchControl.swift) (branch display and switch)

Expected result:

- Stage and unstage move files between sections.
- Discard asks for confirm, then reverts the file.
- Commit with a message creates a commit and clears the staged list.
- Switching branch updates the branch label and the changes list.

## Verify

- cd app/Atelier && swift build -> ok (build complete).
- Launch app on a test repo, stage a file, commit with a message.
- Run git log -1 in a terminal -> shows the commit made from the app.
