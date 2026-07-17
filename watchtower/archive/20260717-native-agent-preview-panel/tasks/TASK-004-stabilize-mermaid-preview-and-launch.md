# TASK-004 Stabilize Mermaid Preview and Launch

Group: C (diagram stability and release verification)

## Brief

Goal: Render Mermaid diagrams without resize flicker, oversized output, or black fallback areas. Complete automated and native UI verification before launch.

Change: Fixed-width per-card snapshots -> responsive cached diagrams with persistent source fallback.

How:

- Measure the panel content width and map it to bounded render width buckets.
- Debounce width changes and avoid rendering for every resize event.
- Keep the previous image visible until the replacement snapshot succeeds.
- Reuse one bounded renderer and cache by Mermaid source plus width bucket.
- Limit cached images and cancel obsolete render requests.
- Keep diagram backgrounds transparent and aligned with Atelier card colors.
- Show selectable source automatically after any parse or render failure.
- Add a clear source toggle and copy action for successful diagrams.
- Test width policy, PNG output, cancellation, cache reuse, and failure fallback.
- Use `$computer-use` for narrow and wide native checks after launch.
- Verify the terminal stays interactive during panel resize and diagram rendering.

Files:

- [app/Atelier/Sources/Atelier/Agent/AgentMarkdownView.swift](app/Atelier/Sources/Atelier/Agent/AgentMarkdownView.swift) (responsive Mermaid card, source controls, and stable loading state)
- [app/Atelier/Sources/Atelier/Terminal/MermaidPreview.swift](app/Atelier/Sources/Atelier/Terminal/MermaidPreview.swift) (bounded renderer, width policy, cache, and cancellation)
- [app/Atelier/Sources/Atelier/Resources/Mermaid/viewer.html](app/Atelier/Sources/Atelier/Resources/Mermaid/viewer.html) (transparent snapshot styling and stable diagram sizing)
- [app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift](app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift) (Mermaid policy, render, cache, and fallback tests)
- [app/Atelier/Sources/Atelier/Terminal/TerminalController.swift](app/Atelier/Sources/Atelier/Terminal/TerminalController.swift) (read-only isolation check; no Mermaid or response changes expected)

Expected result:

- Diagram cards remain visible and stable while the panel resizes.
- Diagrams fit the panel without initial oversized output.
- Invalid source always falls back to selectable and copyable source text.
- Rendering multiple equal diagrams reuses cached output within the cache bound.
- Terminal input, scrollback, and buffer rendering remain unchanged.
- Atelier passes narrow and wide native UI checks and launches successfully.

Prompt:

```text
Use $computer-use after automated checks. Launch Atelier, inspect the preview at 1000 x 700 and 1600 x 1000, resize both layouts, and verify a running Codex or Claude TUI stays interactive.
```

## Verify

- `swift build --package-path app/Atelier` -> build completes without errors.
- `swift test --package-path app/Atelier` -> all tests pass, including Mermaid response tests.
- `app/Atelier/.build/debug/Atelier --selftest` -> all packaged checks pass.
- `rg -n "Mermaid|AgentResponse|AgentPreview" app/Atelier/Sources/Atelier/Terminal/TerminalController.swift` -> no matches.
- `app/Atelier/scripts/build_and_run.sh run` -> the updated app builds, installs, and opens.
- Use `$computer-use` at 1000 x 700 -> overlay layout is readable and the TUI remains mounted.
- Use `$computer-use` at 1600 x 1000 -> docked layout is balanced and resizable.
- Resize a rendered Mermaid card repeatedly -> no blank, black, or oversized intermediate state appears.
- Render invalid Mermaid source -> source fallback appears and remains selectable.
