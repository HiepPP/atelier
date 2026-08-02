# TASK-001 Outcome

## Outcome

Status: DONE

Changed:
- DESIGN.md: added `### Menu Bar` subsection under `## Surface Rules`, after `### Settings`.
- DESIGN.md: extended `## Typography` with the three independent text scale rules.
- DESIGN.md: extended `## Display Sizing and Zoom` with new persistence keys and a derived scale table.
- DESIGN.md: extended `### Settings` with an Appearance section reference and a "Reset appearance" action.

Contract:
- Menu bar panel: fixed 300pt width, `slider.horizontal.3` symbol, rows grouped into Text Size, Display, Code, Actions, native controls with pointer cursor, shares one model with Settings, hiding does not reset stored values.
- Three text scales (app, editor, terminal), range 0.8-1.6, step 0.05, default 1.0.
- New persistence keys: `atelier.appTextScale`, `atelier.editorTextScale`, `atelier.terminalTextScale`, `atelier.manualZoomByDisplay.v1`, `atelier.codeLigaturesEnabled`, `atelier.showsMenuBarExtra`.
- Derived scale formulas for chrome, sidebar, content, terminal, editor documented.

Verified:
- `rg -n "^### Menu Bar" DESIGN.md` -> one match (line 1367).
- `rg -n "atelier.appTextScale|atelier.terminalTextScale|atelier.editorTextScale|atelier.manualZoomByDisplay.v1|atelier.codeLigaturesEnabled|atelier.showsMenuBarExtra" DESIGN.md` -> all six keys appear.
- `rg -n "^#### " DESIGN.md` -> one pre-existing match (`#### Threads`, line 495), not introduced by this change; confirmed via `git diff DESIGN.md | grep "^+" | grep "####"` -> no output.
- `git status --short -- DESIGN.md` -> only DESIGN.md changed.
- Group-level heavy run: `swift build --package-path app/Atelier` -> ok (build complete).
- Group-level heavy run: `swift test --package-path app/Atelier` -> 471 tests in 46 suites passed.
- Group-level heavy run: `app/Atelier/.build/debug/Atelier --selftest` -> SELFTEST: ALL PASS.
