# TASK-003 Outcome

## Outcome

Status: DONE

Changed:

- Split Explorer file callbacks into preview and permanent open intents.
- Mapped native outline single action to preview and double action to permanent open.
- Kept Quick Open, created files, Gemma links, and existing callers on `openFile(_:)`.
- Promoted previews from the native editor change callback before auto-save scheduling.

Contract:

- Explorer is the only preview source.
- Double-click and the first edit promote a preview without changing tab identity.
- Quick Open remains permanent and continues to update recent files.

Verified:

- `swift test --package-path app/Atelier --filter TerminalTabsNavigationTests` -> 10 tests passed.
- `swift build --package-path app/Atelier` -> build completed successfully.
- Native Explorer smoke -> README.md preview was replaced by .gitignore on single-click.
- Native Explorer smoke -> double-clicked README.md remained open after a new preview.
- Native editor smoke -> edited preview fixture remained open after a second preview.
- `app/Atelier/scripts/build_and_run.sh run` -> built, ad hoc signed, installed, and launched Atelier.
- Temporary native smoke fixture -> removed after verification.
- `git diff --check` -> no whitespace errors.
