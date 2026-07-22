# Watchtower Native Panel in Atelier

Rebuild the Watchtower plan dashboard as a native SwiftUI panel inside Atelier,
reading the same `watchtower/` layout the VS Code extension reads.

## Goal

Show the active Watchtower plan (progress, TODO groups, archive) as a native panel
in Atelier, styled with the app theme, with no webview and no Node runtime. Keep
the read-only contract: the `/watchtower` skill writes the Markdown, Atelier only
displays it. The native win is a closed loop: click a TODO and pipe the matching
skill command straight into Atelier's built-in agent.

## Source of Truth

Watchtower lives at `~/Projects/watchtower`. It is a VS Code extension plus a
`/watchtower` skill.

- The skill writes Markdown into a workspace `watchtower/` directory.
- The extension reads that directory and renders a read-only dashboard webview.
- Fixed layout: `watchtower/NEXT.md` (header block plus Tracker table), spec files
  under `watchtower/tasks/` (legacy `todos/`), archived plans under
  `watchtower/archive/<slug>/NEXT.md`.

## Extension vs Native Panel

| Factor | VS Code extension | Watchtower native panel |
|--------|-------------------|-------------------------|
| Render | webview HTML/CSS/JS | native SwiftUI, Atelier theme plus Liquid Glass |
| File watch | VS Code watcher | reuse existing debounced FSEvents (git/file tree) |
| Open file | VS Code command | reuse the new Markdown preview (FilePreview.swift) |
| Parser | TypeScript | pure Swift, deterministic tests under Tests/AtelierTests |
| Run command | copy `/watchtower ...` to clipboard | pipe straight into the built-in agent |
| Runtime | Node process | none, in-process |

The strongest native advantage: the extension can only copy a command. Atelier has
an agent panel. Click a TODO and inject `/watchtower implement TASK-003` into the
agent. Plan and execution live in one app.

## Architecture

Keep the contract intact: the `/watchtower` skill still writes Markdown, Atelier
only reads it. Read-only always. Never write plan files. This matches both the
Watchtower philosophy and the repo destructive-command rules.

```text
Workspace root/watchtower/NEXT.md
  |
  v
WatchtowerParser (pure Swift)  -> Plan / Task (Equatable)
  |
  v
WatchtowerModel (@Observable)  <- debounced FSEvents (watch watchtower/**)
  |
  v
WatchtowerPanelView (SwiftUI)  -> open files via FilePreview, inject commands into Agent
```

### Data Model

Mirror the extension model as Swift value types.

- `PlanStatus`: active, done, archived, unknown.
- `TaskStatus`: todo, inProgress, blocked, done, unknown.
- `Task`: order, id, title, group, status, specPath, outcomePath, deps, notes.
- `Plan`: title, slug, status, updated, manifestPath, tasks, doneCount, totalCount.
- Make `Plan` and `Task` `Equatable` so the view updates only on a real change.

### Parser Port

The TypeScript parser is clean. Port it one to one into pure Swift.

- Header block: slice from `## Current Active Plan`, read Title, Slug, Status, Updated.
- Tracker block: parse the `## Tracker` table. Positional columns: Order, TASK,
  Group, Status, Spec, Deps, Context (unused), Notes.
- Task id: match `TASK-NNN`, accept legacy `TODO-NNN`.
- Spec resolve: take the file name, resolve against `tasks/`, fall back to `todos/`.
  Accept a plain path or a Markdown link cell.
- Task file: find `## Brief`, `## Verify`, `## Outcome` sections. A `Status:` line
  inside Outcome wins over the Tracker status.
- Archive: list subdirectories that contain `NEXT.md`, sort by slug descending.

A pure parser makes deterministic non-UI tests easy, which the repo requires.

## What to Reuse

- Debounced FSEvents watcher already used for git status and the file tree. Watch
  only `watchtower/**`, filter paths through `IgnoreRules` before reacting.
- The new Markdown preview (FilePreview.swift) to open NEXT.md, CONTEXT.md, spec
  files, and archived plans.
- The built-in agent panel (AgentMarkdownView) to run skill commands.
- The workspace root resolution the app already computes for the file tree.

## Crash-Rule Constraints

Follow the repo SwiftUI and AppKit crash rules and performance rules.

- An overlay panel must stay outside `HSplitView` and must not change the proposed
  size of any native content surface at any window width. If it is a split pane,
  keep it mounted and toggle visibility with frame, opacity, and hit testing rather
  than adding or removing the child.
- Never collapse a split child to exactly zero. Keep a positive placeholder width.
- Never mutate `@State` or model state synchronously from a layout-derived value.
  Defer with `Task { @MainActor in ... }` so it runs off the current layout pass.
- Keep all UI mutation on MainActor. Keep strict concurrency on.
- Ban force unwrap, `try!`, `as!`, `fatalError`, and unchecked subscript on any view
  or controller path. Use `guard let` and safe access.

## Performance Constraints

- Diff before reload. `Plan` and `Task` are `Equatable`; update the view only on a
  real change. No redundant invalidation.
- Debounce watcher-driven refreshes with a trailing delay so a burst of FSEvents
  collapses to one refresh and at most one parse pass.
- Precompute status colors (Active, Blocked, Todo, Done). Never allocate `NSColor`,
  `NSFont`, or attribute dictionaries in a draw, layout, or per-row path.
- Cap any long-lived append-only collection, including archive rows.
- Idle CPU must stay in the 0.2 to 2 percent range with the panel open and idle.

## Roadmap

Each step yields a visible result.

1. Port the parser to pure Swift. Add deterministic tests under Tests/AtelierTests
   using fixtures copied from `watchtower/test/fixtures`. Milestone: a mock NEXT.md
   parses into the correct `Plan`.
2. Build the `@Observable` model that reads from the workspace root. Log progress
   and status counts.
3. Build `WatchtowerPanelView`: progress, groups for Active, Blocked, Todo, Done,
   and an archive list.
4. Wire the debounced FSEvents watcher to refresh when `watchtower/` changes.
5. Row click opens the file in the Markdown preview.
6. Wire skill commands into the agent panel. This is the killer feature.

## Verification

- Prove the parser with deterministic tests first, no UI needed.
- After the panel is live, run the native tab switch smoke at full window size and
  confirm no crash and no new report in `~/Library/Logs/DiagnosticReports/`.
- Confirm idle CPU stays in the 0.2 to 2 percent range with the panel open.
- Edit a `watchtower/` file and confirm exactly one debounced refresh, not a burst.

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Watcher refresh storm | Debounce with a trailing delay; diff before reload |
| Layout reentrancy crash | Defer layout-derived mutation; keep the panel mounted |
| Parser drift from the extension | Port one to one; reuse the extension fixtures as tests |
| Writing plan files by mistake | Read-only by design; no write path in the model or view |

## Status

Planning only. No code written yet. Resume at roadmap step 1.
