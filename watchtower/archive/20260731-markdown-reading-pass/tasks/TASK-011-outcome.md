# TASK-011 Outcome

## Outcome

Status: DONE

Changed:

- Dropped `private` from `MarkdownDocumentOutline` in
  [app/Atelier/Sources/Atelier/Editor/FilePreview.swift](app/Atelier/Sources/Atelier/Editor/FilePreview.swift).
  It is shared, not copied. `MarkdownOutlineRow` stays private, because it is used only from inside
  that file.
- Added `showsOutline(headingCount:containerWidth:)` and `activeIndex(headings:answerTop:)` to
  `AgentResponseSectionBarPolicy` in
  [app/Atelier/Sources/Atelier/Agent/AgentResponsesView.swift](app/Atelier/Sources/Atelier/Agent/AgentResponsesView.swift).
  `activeTitle` now reads through `activeIndex`, so the bar and the rail cannot disagree about which
  heading is active. There is one rule, not two.
- Wrapped the transcript in an `HStack` that holds the scroll view and the rail. The rail's entries
  come from one parse per selected response, run in a `.task(id:)` off the render path.
- Row selection scrolls the answer through the existing `MarkdownDocumentScrollSurface`, which was
  already defined but unused. The target is `contentOffsetY + answerTop + heading.y - viewportLead`.
  No document rebuild, and no second scroll surface.
- The pinned section bar now carries `.opacity(showsOutlineRail ? 0 : 1)`, so the bar and the rail
  are never both visible and crossing the breakpoint changes opacity only.

Defect found and fixed during the on-screen check:

- The first version measured the scroll view's width to decide whether to show the rail. That is
  circular: the rail shrinks the scroll view, which can push the width back under the threshold and
  flip the rail off again. The capture showed no rail at a window width that should have had one.
  The gate now measures the container that holds both, so the rail's own width cannot feed back into
  the decision.

Contract:

- The rail is the same component file Preview uses, so it keeps the pointer cursor, the overlay
  scroll chrome, the reading-progress hairline, and the accessibility container.
- Outline state is session-only.
- No layout-derived value writes state synchronously. The container width write is deferred with
  `Task { @MainActor }`.

Verified:

- `rg -c "struct MarkdownDocumentOutline" app/Atelier/Sources/Atelier/` -> exactly one definition.
- `swift test --package-path app/Atelier --filter transcriptOutlineVisibility` -> passed. It asserts
  the rail shows at the exact threshold, hides one point below it, never shows at one heading, and
  that the bar and the rail are never both visible across five widths.
- `swift test --package-path app/Atelier --filter transcriptOutlineSelection` -> passed. It asserts
  the index and the title never disagree across four scroll positions.
- `swift test --package-path app/Atelier --filter transcriptSectionBarVisibility` -> still passes.
- `swift build --package-path app/Atelier` -> build complete, no new warnings.
- `swift test --package-path app/Atelier` -> 438 tests in 41 suites passed in 8.632 seconds.
- `app/Atelier/.build/debug/Atelier --selftest` -> `SELFTEST: ALL PASS`.

On-screen check, window 426901, PID 16211:

- At a 1700 point window the rail renders beside the answer with the `ON THIS PAGE` header, all
  thirteen headings, and the active row `Tóm tắt kế hoạch` carrying the accent left indicator and
  accent label. The pinned bar is hidden.
- At a 1200 point window the rail is gone and the answer takes the full panel.
- Drove the breakpoint five times, 1200, 1700, 1150, 1700, 1200. No crash, no hang.
- `ls -t ~/Library/Logs/DiagnosticReports/ | grep -ci atelier` -> 0.
- `atelier-doctor status --json` -> `status healthy`, `workspace.active true`, settled `cpuPercent`
  0.0111, empty verdict list.
