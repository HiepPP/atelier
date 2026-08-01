# Markdown Reading Pass Design

## Document Status

- Date: 2026-07-31
- Status: Approved design, not yet implemented
- Surfaces: agent Response tab (transcript mode) and Markdown file Preview (document mode)
- Renderer: the shared native attributed builder in
  `app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift`

## Goal

Make both Markdown surfaces easier to read and easier to scan. Stay inside the current
design tokens. Change rhythm, hierarchy, block weight, accent use, and column alignment.
Add one passive scanning aid to the Response tab.

## Non-Goals

- No new design tokens. The tables in `DESIGN.md` under Typography, Spacing, and Color stay as they are.
- No folding, collapsing, or expanding of long content. Code caps, table caps, and answer
  caps are out of scope for this pass.
- No change to parsing, block detection, or the block set.
- No second renderer and no per-mode renderer split.

## Measured Baseline

Read from the builder on 2026-07-31. Transcript at text scale 1.3 and zoom 1.0 resolves body
text to 17.55 points.

| Element | Current rule | Resolved at 17.55 body |
|---|---|---:|
| H1 | `max(28, body * 1.85)` serif semibold | 32.5 |
| H2 | `max(22, body * 1.45)` serif semibold | 25.4 |
| H3 | `max(headline, body * 1.18)` system semibold | 20.7 |
| H4 and deeper | `max(uiSize, body)` system medium, secondary ink | 17.55 |
| Prose line spacing | `spaceS`, absolute | 8 |
| List and table line spacing | `spaceXS`, absolute | 4 |
| Paragraph gap | `rhythm.paragraph` before and after | 0.5u each |
| Code card gap | `rhythm.codeCard` | 1u |
| Divider gap | `rhythm.divider` | 1.5u |
| Table, figure, callout, Mermaid gap | `rhythm.paragraph` | 0.5u |
| Block quote gap | `rhythm.paragraph * 0.5` | 0.25u |

`u` is `bodyFont.lineHeight` snapped to display scale.

## Findings

Each finding names the defect and the evidence behind it.

- **Line spacing is absolute, so the line-height ratio drifts with size.** Real line height is
  `font.lineHeight + lineSpacing`. A flat 8-point addition is a large share of that total at
  transcript scale 0.8, where body text is 10.8 points, and a small share at `editorSize` under 2.0
  zoom, where it is 32 points. So the same rule produces loose text at one end of the range and
  cramped text at the other. Reading comfort is a ratio, not a point value. This is the largest
  single lever in the pass. Implementation measures the exact drift from real font metrics.
- **Heading minimum clamps break the scale.** The `max()` floors mean the H1-to-body ratio is 2.6 at
  transcript scale 0.8 and 1.85 at scale 1.6. Hierarchy changes shape as the reader resizes text.
- **H4 and deeper invert hierarchy.** They resolve to body size in secondary ink, so a heading reads
  quieter than the text it introduces.
- **Display headings carry body leading.** H1 and H2 take the same 8-point extra leading as body
  text. At 32 points of serif that reads loose and unset.
- **Block weight is not encoded in block gaps.** Tables, figures, callouts, and Mermaid figures all
  use `rhythm.paragraph`, the exact gap a plain paragraph gets. A block quote gets half of it. Only
  code cards and dividers separate more than prose does.
- **Terracotta carries nine jobs.** Block quotes, callouts, the question rule, inline code, table
  headers, H3 eyebrows, list bullets, links, and footnote numbers. The two highest-frequency jobs,
  inline code and list bullets, make a technical answer read striped.
- **The response card has two right edges.** The question container is `maxWidth: .infinity` while
  the answer column caps at `transcriptMaxWidth`. At a wide overlay the two edges do not line up.
- **The question is smaller than the answer it heads.** `DESIGN.md` requires the question to read
  "clearly above the answer body size". It is fixed at `headline` 16, while transcript body reaches
  17.55 at the default 1.3 scale.
- **The Response tab has no scanning aid.** File Preview has the On This Page rail and the pinned
  section bar. A long answer is one unbroken column.

## Design

### 1. MarkdownTypeScale

Add one `nonisolated struct MarkdownTypeScale: Sendable`, resolved once per document build from the
resolved body font and `displayScale`. Every paragraph style in the builder reads it. No absolute
point value remains in a rhythm path.

Line spacing is expressed as a target line-height ratio and back-solved against the font's own
line height:

```
lineSpacing = max(0, snapped(fontSize * ratio - font.lineHeight, displayScale: displayScale))
```

| Context | Current rule | Target ratio |
|---|---|---:|
| Prose | `spaceS`, absolute | 1.62 |
| List items | `spaceXS`, absolute | 1.55 |
| Table cells | `spaceXS`, absolute | 1.45 |
| Code lines | zero extra spacing | 1.35 |
| H1 and H2 | `spaceS`, absolute | 1.16 |
| H3 and deeper | `spaceXS`, absolute | 1.30 |

Implementation must record the resolved ratio at transcript scale 0.8, at 1.3, and at `editorSize`
under 2.0 zoom, so the drift claim is checked against real font metrics rather than an assumed
line-height factor.

The scale is resolved during document construction, never during layout or draw.

### 2. Heading Scale

Remove all four `max()` clamps from `headingFont`. Use pure ratios so hierarchy holds its shape at
every text size and zoom. Both modes share one shape at different ranges.

| Level | Face | Weight | Ink | Document | Transcript |
|---|---|---|---|---:|---:|
| H1 | serif | semibold | foreground | 1.85 | 1.45 |
| H2 | serif | semibold | foreground | 1.45 | 1.28 |
| H3 | system | semibold | accent in document, foreground in transcript | 1.18 | 1.12 |
| H4 | system | semibold | foreground | 1.00 | 1.00 |
| H5 and H6 | system | semibold | secondary, `+0.6` tracking | 0.92 | 0.92 |

H4 moving from medium secondary to semibold foreground is what corrects the inverted hierarchy.
The transcript range is compressed because an answer card is not a document title page.

Existing treatments that do not change: the serif face on H1 and H2, the `-0.5` kern on H1 and H2,
the layout-pass heading rule with its long and short accent lead segments, and the document-only
H3 accent eyebrow.

### 3. Block Weight Tiers

Replace the current per-block gap choices with three tiers. Values stay in `u`.

| Tier | Blocks | Before | After |
|---|---|---:|---:|
| Flow | paragraph, list group, lede | 0.5u | 0.5u |
| Structure | code card, table, figure, Mermaid figure, callout, block quote, front matter card | 1.25u | 1.25u |
| Break | divider, H1, H2 | 1.75u | 0.6u |

Notes:

- The block quote moves from 0.25u to 1.25u. That is the largest single change in this section, and
  it is what stops a pull-quote from melting into the paragraph above it.
- H3 keeps its own `1u` before and `0.5u` after. It is a section start, not a break.
- Rows inside a table and lines inside a code card keep zero inter-row spacing. The tier applies to
  the block's outer edges only.
- Resolve every tier value during document build.

### 4. Accent Budget

Cut terracotta from nine jobs to five by demoting the three highest-frequency ones.

| Element | Today | Proposed |
|---|---|---|
| Inline code | accent ink on accent `0.12` fill | primary ink on `raised` fill |
| List bullets | accent, fading toward border by depth | secondary, fading toward border by depth |
| Table header | accent wash | `raised` fill, keeping semibold and light tracking |
| Block quote rule | accent | unchanged |
| Callout rules and glyphs | semantic colors | unchanged |
| Links and link underlines | accent | unchanged |
| Footnote numbers | accent | unchanged |
| H3 eyebrow, document mode | accent | unchanged |

Everything that keeps terracotta is either semantic or interactive. The inline-code geometry does
not change: same fill box derived from the run's font box around its baseline, same horizontal
reservation, same single fill with no outline. Only the two colors change.

The pure-inline-code table cell keeps its single continuous chip so soft-wrapped paths do not
zebra-stripe. It adopts the same neutral fill.

### 5. Response Card Measure

- Cap the question container at `transcriptMaxWidth` so the card presents one right edge.
- Keep leading alignment on both the question and the answer. Do not center the measure; the card
  header sets the left edge.
- Scale the question with the transcript text scale. It is content, not panel chrome, and the
  contract requires it to read above the answer body size. At the default 1.3 scale this puts the
  question at 20.8 against a 17.55 body.
- Panel chrome, controls, and header height keep their own metrics, unchanged.

### 6. Pinned Section Bar in the Response Tab

Reuse the passive section bar already built for file Preview in
`app/Atelier/Sources/Atelier/Editor/FilePreview.swift`.

- Scope: one panel-level bar, not one bar per card.
- Content: the active heading title of the response card that occupies the viewport top, in
  secondary micro type over translucent material with a hairline bottom edge.
- Progress: the same reading-progress accent line along that bottom edge, clamped zero through one.
- Mount rule: show it only while the card owning the viewport top has two or more headings. Hide it
  otherwise.
- Behavior: fully passive. Never hit-test it, never animate it during passive scroll, never let it
  contribute to the measured column width, and never rebuild the attributed document for it.

Wiring: each transcript coordinator already holds the heading character ranges the builder returns.
It exposes them plus its card frame to the panel. The panel picks the owning card from the scroll
bounds observer it already runs. Report only when the visible value changes.

This is the highest-risk item in the pass. It is the only one that needs new cross-card wiring.

## Component Boundaries

| Unit | Responsibility | Depends on |
|---|---|---|
| `MarkdownTypeScale` | Resolve every line-height and block-gap value from one body font and display scale | body font, `displayScale`, presentation mode |
| `headingFont` and `headingColor` | Resolve one heading level to a face, size, weight, and ink | `MarkdownTypeScale`, presentation mode |
| `MarkdownAttributedDocumentBuilder` | Apply the scale and the tiers while emitting the attributed document | `MarkdownTypeScale`, parsed blocks |
| `AgentResponseQuestionView` | Present the question at the card measure and the transcript text scale | `transcriptMaxWidth`, transcript text scale |
| Response panel section bar | Show the active heading and reading progress for the card owning the viewport top | transcript coordinators, panel scroll bounds |

`MarkdownTypeScale` is a pure value type with no AppKit state, so it is testable without a view.
The heading resolvers take the scale as an argument rather than reading global metrics.

## Risks

- **Every paragraph style in the builder changes.** The file is 3684 lines and holds roughly forty
  `paragraphStyle` call sites. A missed site keeps an absolute value and reads out of rhythm at the
  ends of the scale range.
- **Pixel tests will move.** The existing native-render tests assert concrete attributes. They need
  updating alongside, not after.
- **The section bar needs cross-card wiring.** It can be cut without touching sections 1 through 5.
- **Perf paths must stay clean.** No new allocation in draw, layout, or per-row paths. The type
  scale resolves once per build and is captured, never rebuilt during scroll.

## Verification

Repo rules require all of these.

- Update `DESIGN.md` before editing code. The Markdown rules under Editor and Terminal, and the
  Agent Responses rules, both change.
- `swift build --package-path app/Atelier` succeeds with no new warnings.
- `swift test --package-path app/Atelier` passes, including updated native-render assertions.
- `app/Atelier/.build/debug/Atelier --selftest` passes.
- `app/Atelier/scripts/build_and_run.sh run` builds, signs, installs, and launches.
- Idle CPU stays in the 0.2 to 2 percent range after launch, read with `ps -p PID -o %cpu=`.
- On-screen acceptance at full window size: one long answer in the Response tab and one long
  Markdown file in Preview. Confirm heading hierarchy, prose rhythm, quote separation, neutral
  inline code, one card right edge, and the section bar appearing and hiding correctly.
- Drive the transcript text scale to both ends, 0.8 and 1.6, and confirm the line-height ratio and
  heading hierarchy hold their shape.

## Open Item Carried In

The previous plan archived `TASK-006` while still BLOCKED, so the current renderer has never had a
driven on-screen acceptance pass. This pass must not be treated as visually accepted on build and
test results alone.
