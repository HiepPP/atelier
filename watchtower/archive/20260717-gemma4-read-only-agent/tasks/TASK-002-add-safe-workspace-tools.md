# TASK-002 Add Safe Workspace Tools

Group: B (independent read-only tool boundary)

## Brief

Goal: Add three bounded tools that let Gemma inspect the active workspace without changing it.

Change: No agent tools -> validated search, file-read, and Git-diff operations scoped to one workspace.

How:

- Define strict input and result models for `search_workspace`, `read_file`, and `read_git_diff`.
- Resolve file paths against the active workspace after standardization and symlink resolution.
- Reject outside paths, `.git`, `.env`, credentials, and known secret-file patterns.
- Bound file lines, bytes, search matches, Git output, and returned error text.
- Keep file and process work off `MainActor` with cancellation support.
- Reuse the existing Git service for read-only Git operations where it fits.
- Return typed tool errors instead of crashing or silently returning empty output.

Files:

- [app/Atelier/Sources/Atelier/Agent/Tools/WorkspaceToolModels.swift](app/Atelier/Sources/Atelier/Agent/Tools/WorkspaceToolModels.swift) (define the three tool contracts)
- [app/Atelier/Sources/Atelier/Agent/Tools/WorkspaceToolExecutor.swift](app/Atelier/Sources/Atelier/Agent/Tools/WorkspaceToolExecutor.swift) (validate and execute read-only tools)
- [app/Atelier/Tests/AtelierTests/WorkspaceToolExecutorTests.swift](app/Atelier/Tests/AtelierTests/WorkspaceToolExecutorTests.swift) (cover valid reads, bounds, secrets, traversal, symlinks, Git, and cancellation)

Expected result:

- All three tools return useful, bounded workspace context.
- Traversal, symlink escapes, sensitive files, writes, and unknown tools are rejected.
- Tool failures remain typed and safe to return to the model.

## Verify

- `swift test --package-path app/Atelier --filter WorkspaceToolExecutorTests` -> all safety and behavior tests pass.
- Request `../outside.txt` and a symlink outside the fixture root -> both requests are rejected.
- Request a known sensitive fixture -> the request is rejected without returning its contents.
- Cancel a long search -> the operation stops and returns cancellation.
