# Learn 20260731-unify-markdown-renderers

## Summary

Discrepancy: 5 found. The code shipped as planned, but two specs missed behavior the old renderer owned, one Verify line could not pass on correct code, and one TASK planned a tool that is not installed.

## Per TASK

- TASK-001: plan said rewrite the transcript rule and name two modes in [DESIGN.md](DESIGN.md) -> shipped that, then the fixer added two more contract lines for the Mermaid figure width reserve and the transcript code cap. Mistake: none in the work. The contract had to grow because the code grew, and the plan did not foresee either behavior. Fix: expect a docs TASK that runs first to need a second pass after the code lands, or place it last.
- TASK-002: plan said add a `presentation` argument and skip three document-only treatments -> shipped that, plus `AgentCodeBlockPolicy` wiring for `displayedContent` and `copiedContent`. Mistake: spec gap. The old SwiftUI renderer owned an 8,000 character transcript code cap, and no TASK listed it, so the deletion would have dropped it silently. Fix: before deleting a renderer, list the behavior it owns alone, not only the symbols it defines.
- TASK-003: plan said add a self-sizing representable with `sizeThatFits` -> shipped that, plus `figureMeasure()`, which fits a figure to a narrow host, and figure ranges resolved by id instead of a captured range. Mistake: spec gap. The plan assumed one host width, but the Gemma sidecar is 260 to 300 points. Fix: name the narrowest call site in the Brief when a TASK serves five call sites of different widths.
- TASK-004: plan said port the Mermaid toggle and the copy control -> shipped that, and the reviewer found an off-by-one in `MarkdownRegionShift.shifted`. A region starting exactly at the insert point never moved, so a following code block pinned its copy control to the wrong row. Mistake: the Verify line `rg -n "atelierPointerCursor"` cannot pass on correct code, because `AtelierGhostButtonStyle` supplies the cursor and the repo rule bans applying it twice. Fix: the spec line is corrected in this archive. Assert the style, not the token.
- TASK-005: plan said delete the SwiftUI block renderer and migrate the pixel test -> shipped that, and more than the list named. `AgentMarkdownView.swift` went from 2307 to 1495 lines. Mistake: none in the work. The delete list was a starting point, not a full set, and the builder correctly removed the orphans the list implied. Fix: write a delete TASK as an outcome plus a keep list, not as an exact delete list.
- TASK-006: plan said drive three on-screen points with `$computer-use:computer-use` -> archived BLOCKED, never run. Mistake: the plugin is not installed on this machine, so the TASK could never run as written. Nobody checked before the plan was authored or before dispatch. Fix: confirm a named skill or plugin exists before writing it into a Prompt.

## Plan-Level

- The plan collapsed to one group, so `implement team` ran no work in parallel. Wall clock was 51.1 minutes: 31.1 build, 7.3 review, 12.8 fix. The three stages summed exactly, with zero overlap. The team run bought review quality, not speed, and nothing said so before dispatch.
- The grouping rule merged TASK-001 into the code group because of a dependency, not a shared file. TASK-001 writes only [DESIGN.md](DESIGN.md). It ran at opus and xhigh effort for a documentation edit.
- Verification repeated. Each of the five TASKs ran a full build and a full test pass, inside a group whose later TASKs overwrite the earlier ones. One `touch` of [app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift](app/Atelier/Sources/Atelier/Editor/MarkdownSelectableDocumentView.swift) costs 13.06 seconds to recompile, and the 3,740 line test target compiles on top.
- Two of the five specs missed behavior the old renderer owned alone. A replace-and-delete plan needs a behavior inventory step, not only a symbol inventory.
- The archive happens with TASK-006 still BLOCKED. The on-screen acceptance of this renderer is not proved. Carry it into the next plan; do not treat this plan as visually accepted.

## Lessons

- Group TASKs by the files they write. A dependency with no shared file is an order, not a merge. This is now the rule in the watchtower skill.
- Before deleting a code path, inventory the behavior it owns alone. The transcript code cap survived only because a reviewer noticed a policy type had gone dead.
- A Verify line must be able to pass on correct code. A grep for a token that a shared style supplies fails on the better implementation.
- Check that a named skill or plugin is installed before writing it into a TASK Prompt.
- A pre-existing flake surfaced during this plan and is still open: `swift test` can trap in `WorkspaceVisibilityModel.update` because `NSApp` is an implicitly unwrapped optional and is nil in a headless test host. See [app/Atelier/Sources/Atelier/Workspace/Models/WorkspaceVisibilityModel.swift](app/Atelier/Sources/Atelier/Workspace/Models/WorkspaceVisibilityModel.swift). It did not reproduce in three later runs. It is a good candidate for the next plan.
