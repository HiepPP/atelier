# TASK-014 Size the front matter key column from its content

Group: A
Class: code

## Brief

Goal: Stop a deep dotted front-matter key from wrapping mid-word. The user reported
`colors.surface.surface-hover` breaking as `colors.surface.surface-ho` and `ver`.

Cause: `MarkdownFrontMatterLayout.keyColumnPercentage` was a fixed 26 percent. That fits the median
key, 24 characters in the reported file, and wraps the long tail. The cell also wraps by character,
so the break lands mid-word.

How:

- Replace the constant with a function that takes the widest key's measured width, the cell's
  horizontal padding, and the mode measure, then returns a bounded percentage.
- Measure the widest key with the real key font during document build, once per card.
- Bound the result so a short-key document keeps a narrow column and a pathological key cannot
  starve the value column.
- Reserve headroom for the gap between the nominal measure and the real text container. The table
  resolves percentages against the container, which is narrower whenever the window cannot grant the
  full measure.
- Remove the unused `keyColumnWidth` constant.
- Thread the mode measure into `appendFrontMatter`.

Files:

- [app/Atelier/Sources/Atelier/Agent/AgentMarkdownView.swift](app/Atelier/Sources/Atelier/Agent/AgentMarkdownView.swift): replace the constant with the bounded function.
- [app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift](app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift): measure the widest key, take a `measure` argument.
- [DESIGN.md](DESIGN.md): state the content-derived key column rule.
- [app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift](app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift): add a key column test.

Expected result:

- The two 38-character keys in the reported file render on one line each.
- A short-key document keeps the narrow column.

## Verify

- `swift test --package-path app/Atelier --filter frontMatterKeyColumnWidth` -> passes. It asserts
  the narrow floor for a short key, that a deep key widens the column enough to hold itself plus
  padding, that a pathological key clamps to the ceiling, and that a zero measure returns the floor.
- `swift build --package-path app/Atelier` -> build succeeds with no new warnings.
- `swift test --package-path app/Atelier` -> all tests pass.
- Visual: capture the reported file in Preview and confirm
  `colors.text.sidebar-primary-foreground` and `colors.text.sidebar-accent-foreground` each sit on
  one line.
