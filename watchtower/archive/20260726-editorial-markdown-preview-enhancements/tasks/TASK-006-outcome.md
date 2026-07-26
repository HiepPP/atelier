# TASK-006 Outcome

## Outcome

Status: DONE

## Changed

- Added cached native line-number decorations outside the source text.
- Added explicit number and source tab stops to each code paragraph.
- Kept code-card source and syntax-highlight ranges on original characters.

## Contract

- Drawn numbers are outside source characters, so selected copy omits them.
- The card Copy action keeps the exact original fenced source.
- Line-number objects are not allocated during draw.

## Verified

- `swift test --package-path app/Atelier --filter AgentResponsesTests.markdownCodeLineNumbers --quiet` passed.
- `markdownNativeCodeCardMetadata` passed.
- The full-window native fixture showed line numbers 1 through 3. Native `Cmd-C` returned only the three source lines.
- A regression follow-up fixed the draw anchor from the full line fragment to the used text fragment.
- The repeated full-window native fixture kept line numbers 1 through 3 inside the card gutter. Native `Cmd-C` still returned only the three source lines.
- A second regression follow-up corrected the Core Text matrix for flipped native contexts.
- The repeated native fixture showed upright `1`, `2`, and `3` glyphs. The flipped-context test fails without the matrix correction and passes with it.
- `git diff --check` passed.
