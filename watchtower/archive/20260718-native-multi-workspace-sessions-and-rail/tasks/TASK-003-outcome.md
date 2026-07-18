# TASK-003 Outcome

## Outcome

Status: DONE

Changed:

- Added a fixed 56-point outer `WorkspaceRailView` with native workspace identity, selection, hover, press, focus, loading, unavailable, error, and add states.
- Kept every live `WorkspaceView` mounted and isolated while switching visibility to preserve local view and native terminal state.
- Added unavailable workspace recovery content and prevented stale palette responder restoration across workspace changes.
- Routed the rail, empty state, toolbar, menu, and palette workspace actions through `AtelierActionRegistry`.
- Added deterministic rail sizing and active-session action routing tests.
- Fixed failed opens so catalog items remain unavailable instead of appearing inactive.
- Resigned the old AppKit first responder on workspace switches and invalidated pending restores.
- Tracked responder ownership by workspace so stale focus cannot return to an inactive session.
- Enabled Close Workspace for selected unavailable catalog items without enabling live-session actions.
- Added distinct error recovery icon, title, message, and accessibility value.

Contract:

- Rail remains outside `WorkspaceView` in compact, standard, wide, and focus modes.
- Workspace-scoped actions resolve `AppModel.workspace` at invocation time.
- Inactive sessions remain mounted, running, non-interactive, and hidden from accessibility.
- Plus control uses the existing folder picker with explicit hover, press, focus, label, value, and help states.
- Selection uses existing Atelier tokens, a thin leading accent rule, native text, and SF Symbols.
- Focused commands cannot remain attached to an inactive mounted workspace.
- Any selected catalog item can close, even when it has no live session.
- Error recovery stays visually and semantically distinct from unavailable-folder recovery.

Verified:

- `swift build --package-path app/Atelier` passed.
- `swift test --package-path app/Atelier` passed 121 tests in 13 suites.
- `app/Atelier/.build/debug/Atelier --selftest` passed all checks.
- `app/Atelier/scripts/build_and_run.sh run` built, ad hoc signed, installed, and launched PID 81530.
- Responder policy tests reject inactive owners, unowned responders, and stale restore revisions.
- Action tests close a selected unavailable item while keeping terminal actions disabled.
- Recovery policy tests prove error and unavailable presentations use different semantics.
- Main Computer Use check passed ten workspace switches with accessibility state intact.
- Native light-mode screenshots passed at exact 760 x 512 and 1440 x 900 content sizes with no overlap, clipping, or lost center navigation.
- Console scan found no constraint-loop, detached-responder, or terminal-teardown warnings.
- `git diff --check` passed.
- Direct caller analysis found no high-risk blast radius. GitNexus was unavailable because Atelier has no index.
- Main Computer Use AX inspection confirmed workspace names, selected and available values, Add workspace labeling, active project commands, and terminal visibility.
- Source audit confirmed dynamic Atelier colors for dark appearance, solid rail fills for Reduce Transparency, and disabled optional press animation under Reduce Motion.
- Physical VoiceOver audio and system accessibility toggles were not changed during verification.

Initial verification failures fixed during implementation:

- Compile failed on a nonisolated rail metric reference and incorrect `AtelierEmptyState` arguments.
- Test compile failed because `AtelierActionRegistryTests.swift` lacked `Foundation`.
