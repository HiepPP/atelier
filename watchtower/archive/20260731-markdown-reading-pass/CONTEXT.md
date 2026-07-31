# Context

## Plan Context

This plan makes both Markdown surfaces easier to read. It follows the approved design at
[docs/superpowers/specs/2026-07-31-markdown-reading-pass-design.md](docs/superpowers/specs/2026-07-31-markdown-reading-pass-design.md).
Read that spec before starting any TASK. It holds the measured baseline, the findings, and the
target values.

## Surfaces

- Response tab, transcript mode. Host is
  [app/Atelier/Sources/Atelier/Agent/AgentResponsesView.swift](app/Atelier/Sources/Atelier/Agent/AgentResponsesView.swift).
- Markdown file Preview, document mode. Host is
  [app/Atelier/Sources/Atelier/Editor/FilePreview.swift](app/Atelier/Sources/Atelier/Editor/FilePreview.swift).
- Both render through one builder,
  [app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift](app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift).
- The self-sizing native host lives in
  [app/Atelier/Sources/Atelier/Agent/AgentMarkdownView.swift](app/Atelier/Sources/Atelier/Agent/AgentMarkdownView.swift).

## Hard Rules

- Do not add a second Markdown code path. Add to the shared builder instead.
- Do not add new design tokens. The plan stays inside the current Typography, Spacing, and Color
  tables in [DESIGN.md](DESIGN.md).
- Update [DESIGN.md](DESIGN.md) before changing code. The repo treats it as the design contract.
- Resolve every value during document construction. Never allocate a font, color, or paragraph
  style in a draw, layout, or per-row path.
- No folding, collapsing, or expanding of long content. That is out of scope for this plan.
- Every clickable control shows the link pointer cursor. `AtelierGhostButtonStyle` already supplies
  it, so never apply `.atelierPointerCursor()` twice and never grep for that token in a Verify line.

## Shared Test File

Group A and Group B both write
[app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift](app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift).
Do not run these two groups in parallel. Run them in Tracker order.

## Verification Bias

- `swift build --package-path app/Atelier`
- `swift test --package-path app/Atelier`
- `app/Atelier/.build/debug/Atelier --selftest`
- `app/Atelier/scripts/build_and_run.sh run`

No `computer-use` plugin is installed on this machine. On-screen acceptance is a separate TASK for a
human at the screen. Do not bury on-screen checks inside a code TASK's Verify list.
