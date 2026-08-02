# TASK-001 Design contract for appearance settings

Group: docs
Class: docs

## Brief

Goal: Update [DESIGN.md](DESIGN.md) so it describes the menu bar item and the new appearance
settings before any code changes.

Change: add one new surface section for the menu bar item, and extend the typography, sizing, and
settings sections with the new scales and keys.

How:

- Add a new subsection `### Menu Bar` under `## Surface Rules`, after `### Settings`. Write these
  rules:
  - Atelier shows one menu bar item with the `slider.horizontal.3` symbol.
  - The item opens a panel, not a plain menu list. Use a fixed 300-point width.
  - The panel groups rows into Text Size, Display, Code, and Actions.
  - Every row uses a native control with the pointer cursor.
  - The panel repeats controls that also exist in the Settings window. Both read one model.
  - The user can hide the item from the Settings window. Hiding it never changes stored values.
- Extend `## Typography`. Add a paragraph after the type rules:
  - Three independent text scales multiply the tokens: app text, editor text, and terminal text.
  - Each scale stays between 0.8 and 1.6 and moves in 0.05 steps. The default is 1.0.
  - App text scales interface tokens. Editor text scales `editorSize`. Terminal text scales
    `terminalSize`.
  - Code ligatures are a user setting. The terminal applies a change at once. The editor and the
    Markdown preview apply it the next time the file opens.
- Extend `## Display Sizing and Zoom` rules:
  - Replace "Store manual zoom per display during the app session" with "Store manual zoom per
    display and restore it on the next launch, under `atelier.manualZoomByDisplay.v1`".
  - Add: "Persist the app, editor, and terminal text scales under `atelier.appTextScale`,
    `atelier.editorTextScale`, and `atelier.terminalTextScale`."
  - Add: "Persist code ligatures under `atelier.codeLigaturesEnabled` and menu bar visibility under
    `atelier.showsMenuBarExtra`."
  - Add the derived scale table: chrome and sidebar caps stay at 1.2 and 1.5, content uses
    `renderScale * appTextScale`, terminal uses `renderScale * terminalTextScale`, editor uses
    `renderScale * editorTextScale`.
- Extend `### Settings`:
  - Add an Appearance section that carries the same controls as the menu bar panel.
  - Add a "Reset appearance" action that returns zoom and all three text scales to their defaults.
- Keep the document style: H2 and H3 only, no bold, no emojis, short sentences.

Files:

- [DESIGN.md](DESIGN.md): new `### Menu Bar` subsection, extended `## Typography`,
  `## Display Sizing and Zoom`, and `### Settings`.

Expected result:

- DESIGN.md describes the menu bar panel, the three text scales, the persistence keys, and the
  reset action.
- No code file changes in this TASK.

## Verify

- `rg -n "^### Menu Bar" DESIGN.md` -> one match.
- `rg -n "atelier.appTextScale|atelier.terminalTextScale|atelier.editorTextScale|atelier.manualZoomByDisplay.v1|atelier.codeLigaturesEnabled|atelier.showsMenuBarExtra" DESIGN.md`
  -> all six keys appear.
- `rg -n "^#### " DESIGN.md` -> no match, so heading depth stays at H3.
- `git status --short -- DESIGN.md` -> only DESIGN.md changed.
