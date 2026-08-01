# TASK-013 Parse long front matter with quoted keys

Group: A
Class: code

## Brief

Goal: Fix a reported break. A real design-system `DESIGN.md` rendered its front matter as a divider
followed by one run-on paragraph of every field joined together, instead of the metadata card.

Reported by the user with a screenshot of
[/Users/hiep/Projects/proto-cube-pvs/DESIGN.md](/Users/hiep/Projects/proto-cube-pvs/DESIGN.md) in
Markdown Preview.

Cause: two independent limits in `MarkdownFrontMatterPolicy`, either of which alone breaks the block.

- The file's front matter runs lines 1 to 187, so 186 content lines. `maximumLineCount` was 64, so
  the scan gave up before reaching the closing marker and returned nil.
- Three lines use quoted numeric keys, `"2": "border-2"`, `"4"`, and `"8"`. `field` checked the key
  charset before unquoting, so the `"` character failed it and returned nil.

Once `parse` returns nil the document falls back to block parsing. The opening `---` becomes a
divider, and Markdown lazy continuation joins every following `key: value` line into one paragraph.

How:

- Raise `maximumLineCount` to 512 and say in the comment what the bound is actually for: stopping a
  stray `---` from making the parser read a whole document.
- Unquote the key before the charset check in `field`, reusing the existing `unquoted` helper that
  already handles values.
- Update [DESIGN.md](DESIGN.md) to state both behaviors.

Files:

- [app/Atelier/Sources/Atelier/Agent/AgentMarkdownView.swift](app/Atelier/Sources/Atelier/Agent/AgentMarkdownView.swift):
  raise the scan bound, unquote the key.
- [DESIGN.md](DESIGN.md): state the quoted-key rule and the 512-line scan bound.
- [app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift](app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift):
  add a long-front-matter test and a stray-divider test.

Expected result:

- A 186-line front matter block with quoted numeric keys renders as the metadata card.
- A stray `---` with no closing marker still renders as a divider.

## Verify

- `swift test --package-path app/Atelier --filter longFrontMatterWithQuotedKeys` -> passes. It builds
  a 185-line block with quoted numeric keys, asserts the entry count and end index, and asserts the
  document's first block is `.frontMatter` with no `.divider` anywhere.
- `swift test --package-path app/Atelier --filter strayDividerIsNotFrontMatter` -> passes, so the
  fallback still works and a plain divider keeps its meaning.
- `swift build --package-path app/Atelier` -> build succeeds with no new warnings.
- `swift test --package-path app/Atelier` -> all tests pass.
- Visual: open the reported file in Markdown Preview and confirm the H1, then the masthead row, then
  the key and value card. No divider ornament, no run-on paragraph.
