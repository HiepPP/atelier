# TASK-007 Pin a section bar in the Response tab

Group: B
Class: risky

## Brief

Goal: Give the Response tab the scanning aid that file Preview already has. A long answer is one
unbroken column today.

Change: Reuse `MarkdownStickySectionBar` at panel level in the response overlay.

How:

- `MarkdownStickySectionBar` is currently `private` in
  [app/Atelier/Sources/Atelier/Editor/FilePreview.swift](app/Atelier/Sources/Atelier/Editor/FilePreview.swift)
  at line 400. Make it internal and move it to a shared location, or leave it in place and drop the
  `private`. Pick the smaller change. Do not copy it.
- Expose the rendered heading ranges from `MarkdownTranscriptCoordinator`. The builder already
  returns them; the coordinator holds the result. Add a read-only accessor.
- In the response panel, observe the scroll bounds the panel already runs. Pick the response card
  that owns the viewport top.
- Map that card's scroll offset to its active heading with the existing
  `MarkdownOutlineSyncPolicy.activeOutlineID`. Do not write a second policy.
- Mount the bar only when the owning card's answer has two or more headings. Change opacity when the
  condition flips. Never insert or remove the view during a layout pass.
- Draw the reading progress line on the bar's bottom edge, clamped zero through one, using the same
  treatment file Preview uses.
- Keep it passive. Never hit-test it. Never animate it during passive scroll. Never let it change the
  measured column width. Never rebuild the attributed document for it.
- Report the active heading only when the visible value changes. A per-scroll state write would
  re-render the panel on every frame.
- Defer any state mutation that comes from a layout-derived value with `Task { @MainActor in ... }`.
  A synchronous write from a size or offset change traps in AppKit's layout pass.

Files:

- [app/Atelier/Sources/Atelier/Editor/FilePreview.swift](app/Atelier/Sources/Atelier/Editor/FilePreview.swift):
  drop `private` from `MarkdownStickySectionBar`, or move it to a shared file.
- [app/Atelier/Sources/Atelier/Agent/AgentMarkdownView.swift](app/Atelier/Sources/Atelier/Agent/AgentMarkdownView.swift):
  expose heading ranges from `MarkdownTranscriptCoordinator`.
- [app/Atelier/Sources/Atelier/Agent/AgentResponsesView.swift](app/Atelier/Sources/Atelier/Agent/AgentResponsesView.swift):
  add the panel-level bar, the owning-card rule, and the progress value.

Expected result:

- Scrolling a long answer with two or more headings shows the active heading in the pinned bar.
- The bar hides when the owning answer has fewer than two headings.
- The reading progress line tracks the owning card's scroll position.
- Idle CPU stays between 0.2 and 2 percent with the panel open and no interaction.

Prompt:

```text
This is the only item in the plan needing new cross-card wiring.
If the owning-card rule turns out to need a new scroll observer, stop and report before adding one.
Cutting this TASK does not block any other TASK in the plan.
```

## Verify

- `rg -n "private struct MarkdownStickySectionBar" app/Atelier/Sources/Atelier/Editor/FilePreview.swift` -> no match, so the bar is shared, not copied.
- `rg -c "struct MarkdownStickySectionBar" app/Atelier/Sources/Atelier/` -> exactly one definition in
  the whole source tree.
- `swift test --package-path app/Atelier --filter transcriptSectionBarVisibility` -> the new test
  passes. It asserts the bar mounts at two headings and hides at one.
- `swift build --package-path app/Atelier` -> build succeeds with no new warnings.
- `swift test --package-path app/Atelier` -> all tests pass.
- `app/Atelier/.build/debug/Atelier --selftest` -> `SELFTEST: ALL PASS`.
- `ps -p <PID> -o %cpu=` after the app settles for 30 seconds -> idle CPU stays between 0.2 and 2
  percent with the response overlay open.
- The visual check of the bar belongs to TASK-008. Do not claim it here.
