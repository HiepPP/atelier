# TASK-003 Add the native workspace rail

Group: A (contract, state engine, and workspace rail ship as one feature)

## Brief

Goal: Add a polished outer-left workspace rail for adding, selecting, and reading workspace state. Keep all action surfaces on the active session.

Change: Empty or single workspace content fills the window -> a persistent outer rail wraps empty and active workspace content.

How:

- Use `design-taste-frontend` to review hierarchy and remove generic AI styling.
- Run required impact analysis before changing each symbol.
- Add one focused `WorkspaceRailView` instead of expanding the large workspace view.
- Keep the rail outside `WorkspaceView`, its sidebar, center tabs, inspector, and status bar.
- Render workspace identity with stable native text or SF Symbols and no decorative duplicates.
- Add clear selected, hover, pressed, focus, loading, unavailable, error, and disabled states.
- Add one quiet `+` control that calls the existing folder picker flow.
- Activate existing sessions without rebuilding `WorkspaceView` state.
- Keep the rail usable when no workspace is active.
- Route menu and palette workspace actions through `AtelierActionRegistry`.
- Keep commands, Quick Open, new terminal, navigation, Git, and agent actions bound to the active session.
- Preserve keyboard focus across switching and reject responders owned by another session.
- Follow the contract for focus mode, narrow layout, wide layout, and accessibility.
- Add deterministic action, rail policy, and sizing tests.
- Run native checks at exact narrow and wide window sizes.

Files:

- [app/Atelier/Sources/Atelier/Workspace/Views/WorkspaceRailView.swift](app/Atelier/Sources/Atelier/Workspace/Views/WorkspaceRailView.swift) (add the focused rail view and local item states)
- [app/Atelier/Sources/Atelier/Workspace/Views/ContentView.swift](app/Atelier/Sources/Atelier/Workspace/Views/ContentView.swift) (compose the rail around empty and active content)
- [app/Atelier/Sources/Atelier/Theme/AtelierTheme.swift](app/Atelier/Sources/Atelier/Theme/AtelierTheme.swift) (add only shared rail metrics required by the contract)
- [app/Atelier/Sources/Atelier/Commands/AtelierActionRegistry.swift](app/Atelier/Sources/Atelier/Commands/AtelierActionRegistry.swift) (bind workspace actions to active-session semantics)
- [app/Atelier/Sources/Atelier/App/AppCommands.swift](app/Atelier/Sources/Atelier/App/AppCommands.swift) (keep menu titles and enabled states correct)
- [app/Atelier/Tests/AtelierTests/AtelierActionRegistryTests.swift](app/Atelier/Tests/AtelierTests/AtelierActionRegistryTests.swift) (verify active-session action routing)
- [app/Atelier/Tests/AtelierTests/DisplaySizingTests.swift](app/Atelier/Tests/AtelierTests/DisplaySizingTests.swift) (verify rail metrics and layout policy)

Expected result:

- The rail stays at the outer-left edge with clear native hierarchy.
- The `+` control adds or selects a workspace through the current folder picker.
- Switching restores each session's exact in-memory state without terminal teardown.
- Active, inactive, unavailable, and error states remain clear without strong visual noise.
- Narrow and wide layouts stay usable and match [DESIGN.md](DESIGN.md).
- Keyboard, focus, help text, accessibility labels, and system appearance work correctly.

Prompt:

```text
Use design-taste-frontend as an anti-slop audit, then implement the native workspace rail defined in DESIGN.md. Follow required GitNexus impact checks before edits. Keep the rail outside WorkspaceView and preserve active-session action routing. Use existing Atelier tokens, native controls, SF Symbols, thin rules, and restrained motion. Avoid Slack imitation, web dashboards, gradients, heavy shadows, pills, and oversized cards. Verify exact 760 x 512 and 1440 x 900 layouts.
```

## Verify

- `swift build --package-path app/Atelier` -> the rail and action integration compile.
- `swift test --package-path app/Atelier` -> action, sizing, lifecycle, and existing tests pass.
- `app/Atelier/.build/debug/Atelier --selftest` -> packaged checks pass.
- `app/Atelier/scripts/build_and_run.sh run` -> Atelier builds, installs, and opens.
- Open two workspaces, create different tabs and terminals, then switch ten times -> both sessions remain exact and alive.
- Select the same folder through `+` -> the existing item activates and no duplicate appears.
- Move one saved folder, relaunch, and switch -> its unavailable state does not block valid workspaces.
- Check `760 x 512` and `1440 x 900` -> no overlap, clipping, or lost center navigation.
- Check light and dark appearance -> selection and status remain readable.
- Check keyboard and VoiceOver labels -> every rail item and icon-only control has clear state and purpose.
- Check Reduce Motion and Reduce Transparency -> optional effects stop and solid fills remain readable.
- Inspect console output -> no constraint-loop, detached-responder, or terminal teardown warnings appear.
