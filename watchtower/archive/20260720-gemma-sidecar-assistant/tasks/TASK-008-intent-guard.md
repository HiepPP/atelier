# TASK-008 Intent Guard

Group: E (standalone feature on top of the sidecar)

## Brief

Goal: user states a session intent; Gemma warns when the working diff drifts outside that intent.

Change: scope creep goes unnoticed -> sidecar shows a quiet drift warning naming out-of-scope files.

How:

- Add an intent field at the top of the sidecar (one line, for example "fix scrollbar spacing"). Empty intent disables the feature.
- After meaningful diff growth (checked at most every few minutes via `git status` and diff stat), run one bounded Gemma call: intent plus changed file list plus diff summary. Ask: which changed files do not serve this intent?
- Show a small warning row listing out-of-scope files. Dismissing it suppresses warnings until the file set changes again.
- Never block anything; this is advisory only. Skip when Ollama is unreachable.

Files:

- [app/Atelier/Sources/Atelier/Agent/](app/Atelier/Sources/Atelier/Agent/) (intent state and drift check in sidecar model)
- [app/Atelier/Sources/Atelier/Workspace/Views/ContentView.swift](app/Atelier/Sources/Atelier/Workspace/Views/ContentView.swift) (intent field and warning row)

Expected result:

- With intent "fix terminal spacing", edits under an unrelated area produce a drift warning naming those files.
- Edits matching the intent produce no warning.
- Empty intent produces no checks and no calls.

## Verify

- `swift build --package-path app/Atelier` -> builds clean.
- `swift test --package-path app/Atelier` -> tests cover empty-intent skip and dismiss suppression.
- Manual: set intent, edit an unrelated file -> warning lists that file; dismiss -> warning stays hidden until new files change.
