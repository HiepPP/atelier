# TASK-001 Update the Markdown design contract

Group: A (the contract must land before the code that follows it)

## Brief

Goal: Update [DESIGN.md](DESIGN.md) so it describes one Markdown renderer with two presentation modes. Today it describes the file-preview surface and the transcript surface as separate treatments.

Change: two described Markdown treatments -> one native surface with a document mode and a transcript mode.

How:

- Read the Markdown sections of [DESIGN.md](DESIGN.md): the file Preview rules near line 864 and the transcript rule near line 1204.
- Rewrite the transcript rule. State that agent responses render through the same native attributed document as file Preview.
- Name the two modes. Document mode uses `editorSize` body text and the `documentMaxWidth` measure. Transcript mode uses `body` size and the `transcriptMaxWidth` measure.
- State that the transcript surface does not scroll itself. Its host scroll view owns scrolling.
- State that transcript mode keeps the Mermaid source toggle and the icon-only copy control.
- Keep the token table near line 123 unchanged. Both measures stay.

Files:

- [DESIGN.md](DESIGN.md) (rewrite the transcript Markdown rule, extend the Preview rules with the two modes)

Expected result:

- `DESIGN.md` names one renderer and two presentation modes.
- `DESIGN.md` no longer implies two separate Markdown implementations.
- No source file changes in this TASK.

## Verify

- `rg -n "transcript mode|document mode" DESIGN.md` -> both modes appear in the Markdown sections.
- `rg -n "consistent with the file-preview surface" DESIGN.md` -> no match, because the old parity wording is gone.
- `git diff --stat` -> only `DESIGN.md` changed.
