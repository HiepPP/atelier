# TASK-001 Outcome

## Outcome

Status: DONE

## Changed

- `DESIGN.md` (Markdown Preview rules, Mermaid rules, agent transcript rules)

## Contract

One Markdown renderer with two presentation modes. Document mode uses `editorSize` body text and the
`documentMaxWidth` measure plus the three document-only treatments (lede scale, front-matter
masthead, H3 accent eyebrow). Transcript mode uses `body` size and `transcriptMaxWidth`, skips those
three, and keeps every other block treatment. The transcript text view does not scroll itself; its
host scroll view owns scrolling. Transcript mode keeps the icon-only Copy control and the Mermaid
source toggle; both surfaces get the Mermaid toggle. Token table near line 123 unchanged.

## Verified

- `rg -n "transcript mode|document mode" DESIGN.md` -> lines 1221 and 1225 match. Capitalized
  "Document mode" and "Transcript mode" also appear at lines 877-882.
- `rg -c "consistent with the file-preview surface" DESIGN.md` -> no match.
- `git diff --stat` -> `DESIGN.md | 26 ++++---`, 23 insertions, 3 deletions. Only DESIGN.md changed.

## Review fixes

Two contract lines were added after review, because the code changed behavior that the contract did
not describe.

- Mermaid rules: the figure paragraph and the figure width now reserve trailing room for the source
  toggle, and a figure fits the host text container when the host is narrower than the mode measure.
- Agent transcript rules: a transcript code card is capped at the shared code-block display limit,
  its Copy action still returns the whole source, and file Preview keeps the full file.
- `rg -n "transcript mode|document mode" DESIGN.md` -> still matches. `rg -n "consistent with the
  file-preview surface" DESIGN.md` -> still no match.
