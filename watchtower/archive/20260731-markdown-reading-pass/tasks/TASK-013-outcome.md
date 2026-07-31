# TASK-013 Outcome

## Outcome

Status: DONE

Changed:

- Raised `MarkdownFrontMatterPolicy.maximumLineCount` from 64 to 512 in
  [app/Atelier/Sources/Atelier/Agent/AgentMarkdownView.swift](app/Atelier/Sources/Atelier/Agent/AgentMarkdownView.swift),
  and wrote what the bound is for: stopping a stray `---` from making the parser read a whole
  document, not capping how long real front matter may be.
- `field` now unquotes the key before the charset check, reusing the existing `unquoted` helper.
  YAML requires quotes on a numeric key, so `"2": "border-2"` was being rejected.
- Stated both behaviors in [DESIGN.md](DESIGN.md).
- Added `longFrontMatterWithQuotedKeys` and `strayDividerIsNotFrontMatter` in
  [app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift](app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift).

Cause, confirmed against the reported file:

- Front matter in
  [/Users/hiep/Projects/proto-cube-pvs/DESIGN.md](/Users/hiep/Projects/proto-cube-pvs/DESIGN.md)
  runs lines 1 to 187, so 186 content lines against a 64-line bound.
- Three lines carry quoted numeric keys: `"2"`, `"4"`, `"8"` under `radius`.
- Either limit alone returns nil from `parse`, and the fallback then makes the opening `---` a
  divider and lets lazy continuation join all 156 fields into one paragraph. That is exactly what the
  screenshot showed.

Contract:

- A stray `---` with no closing marker still falls back to a divider. That path is now covered by a
  test, which it was not before.
- Nesting, list continuation, value unquoting, the masthead, and the card layout are unchanged.

Verified:

- `swift test --package-path app/Atelier --filter longFrontMatterWithQuotedKeys` -> passed. Asserts
  183 entries, the end index, the dotted key `radius.2`, that the first block is `.frontMatter`, and
  that no `.divider` block exists.
- `swift test --package-path app/Atelier --filter strayDividerIsNotFrontMatter` -> passed.
- `swift build --package-path app/Atelier` -> build complete, no new warnings.
- `swift test --package-path app/Atelier` -> 440 tests in 41 suites passed in 8.862 seconds.
- `app/Atelier/.build/debug/Atelier --selftest` -> `SELFTEST: ALL PASS`.
- Simulated the shipped parser rules against the real file before touching the app: it now reaches
  the closing marker at line 187 and yields 156 entries. Before, it stopped at line 65.

On-screen check, window 427483:

- The reported file now renders the H1 `tini-library - Design Guideline for AI Agents`, then the
  accent micro masthead row carrying `Proto Cube PVS Design System`,
  `@tini-works/tokens@4.0.1`, and `@tini-works/json-render-shadcn@3.2.0`, then the quiet key and
  value card with dotted key paths such as `colors.surface.background`.
- No divider ornament and no run-on paragraph.

Two smaller things seen while checking, no TASK yet:

- A long dotted key wraps mid-word in the key column, so `colors.surface.surface-hover` breaks as
  `colors.surface.surface-ho` and `ver`. The key column is 26 percent of the measure and wraps by
  character.
- A front-matter value that contains backticks shows them literally, for example ``CSS-var-backed by
  `@tini-works/tokens@4.0.1` ``. Values are rendered as plain text, which is faithful to YAML but
  reads oddly beside inline code everywhere else.
