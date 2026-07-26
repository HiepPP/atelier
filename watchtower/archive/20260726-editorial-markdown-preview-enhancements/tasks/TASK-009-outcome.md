# TASK-009 Outcome

## Outcome

Status: DONE

## Changed

- Collected one-line footnote definitions outside normal block flow.
- Added stable first-reference numbering and accent superscript references.
- Added one trailing native Notes table and transcript equivalent.

## Contract

- Resolved syntax is hidden. Unresolved syntax remains literal.
- Notes use numbered secondary rows and do not enter the outline.
- Numbering and inline cache keys remain stable for the parsed document.

## Verified

- `swift test --package-path app/Atelier --filter AgentResponsesTests.markdownFootnotes --quiet` passed.
- The mixed fixture covers repeated, resolved, unresolved, transcript, and table-cell references.
- The full-window native fixture showed stable superscript references and one numbered Notes section outside the outline.
- `swift build --package-path app/Atelier` and packaged selftest passed.
- Full `swift test --package-path app/Atelier --quiet` later passed all 282 tests after the Git pipe inheritance fix.
- `git diff --check` passed.
