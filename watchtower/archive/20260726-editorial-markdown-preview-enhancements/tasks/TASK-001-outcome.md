# TASK-001 Outcome

## Outcome

Status: DONE

## Changed

- Added five semantic GitHub callout kinds to the shared Markdown parser.
- Added matching transcript cards and native `NSTextTableBlock` cards.
- Kept ordinary block quotes on their existing pull-quote path.

## Contract

- Literal callout markers are removed.
- Labels use existing semantic colors. Bodies remain selectable and full contrast.
- Parsing and rendering stay deterministic during document construction.

## Verified

- `swift test --package-path app/Atelier --filter AgentResponsesTests.markdownCallout --quiet` passed.
- The focused fixture confirms ordinary quotes still parse as `.quote`.
- The full-window native fixture showed distinct NOTE and WARNING cards beside the ordinary pull quote.
- `git diff --check` passed.
