# TASK-001 Define the multi-workspace contract

Group: A (contract, state engine, and workspace rail ship as one feature)

## Brief

Goal: Update the product and design contracts before changing Swift code. Define one clear multi-workspace model and native rail behavior.

Change: One active workspace shell -> one workspace catalog with an outer rail and one selected live session.

How:

- Use `design-taste-frontend` as an anti-slop audit for hierarchy, spacing, and icon choices.
- Update the interface tree with the rail outside the active `WorkspaceView`.
- Define the rail width token, item anatomy, spacing, selection, focus, hover, pressed, and disabled states.
- Define active, inactive, loading, unavailable, error, and empty catalog behavior.
- Define compact, standard, wide, focus mode, light, dark, and accessibility behavior.
- State that switching keeps inactive sessions alive and isolated.
- State that the catalog persists, while tab and terminal state remains session-only.
- Update architecture ownership from one active workspace to a catalog of live sessions.
- Keep the design native to macOS. Do not copy Slack's colors, shapes, or branding.

Files:

- [DESIGN.md](DESIGN.md) (add the rail, states, tokens, interactions, and verification contract)
- [README.md](README.md) (update features and application state ownership)

Expected result:

- Both documents describe the same multi-workspace architecture.
- The rail has an exact visual and interaction contract before implementation.
- Runtime state isolation and persistence boundaries are explicit.
- No Swift source changes in this TASK.

Prompt:

```text
Use design-taste-frontend to audit the proposed workspace rail. Keep only anti-slop guidance that fits a dense native macOS IDE. Update DESIGN.md before implementation. Define exact rail anatomy, state matrix, accessibility, responsive behavior, and state ownership. Update README.md to match. Do not implement Swift code in this TASK.
```

## Verify

- `git diff --check -- DESIGN.md README.md` -> documentation changes have no whitespace errors.
- Review the interface tree -> the rail wraps empty and active workspace content at the outer-left edge.
- Review the state matrix -> active, inactive, loading, unavailable, error, and empty states are defined.
- Review persistence rules -> catalog identity persists and runtime tabs remain session-only.
- Review design rules -> no web dashboard, Slack clone, gradient, heavy shadow, or oversized card pattern appears.
