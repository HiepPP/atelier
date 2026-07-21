# Plan Context

## Shared Context

- The feature adds a workspace threads panel like Zed IDE. It tracks terminals that run an agent.
- A thread is a terminal that runs or ran an agent, such as `claude` or `codex`. Plain shell terminals do not appear.
- Placement is inside each workspace group in the left Workspace panel.
- Each workspace header and its nested thread rows have separate click targets. There is no Threads tab.
- The panel groups threads by workspace and lists every live workspace, not only the active one. This matches the Zed layout in the reference image.
- Detection reads the foreground process of each terminal pty and matches an agent name list. It does not rely on shell integration.
- Atelier does not inject shell integration, so OSC 133 marks fire only when the user shell already emits them. Do not depend on OSC 133 for detection.
- Lifecycle: a thread stays while its terminal is open. Status moves from running to done. Closing the terminal removes the thread. There is no separate history store.
- Performance: refresh runs only while the Workspace panel is mounted and the app is active.
- Clicking a thread activates its workspace when needed, then focuses the matching terminal tab in the center.

## Decisions

- Thread scope is agent terminals only, chosen by the user over all terminals or all center tabs.
- Detection uses foreground process inspection, chosen by the user for a light and reliable path.
- Lifecycle keeps a done thread while the terminal is open, chosen by the user over a Zed-style history store.
- Data approach A: derive thread groups on demand from live sessions. Do not add a per-run history store. Keep a small run-state map keyed by terminal id so a done row survives a panel close and reopen.
- The panel model lives at app level in [app/Atelier/Sources/Atelier/App/AppModel.swift](app/Atelier/Sources/Atelier/App/AppModel.swift) so run state survives panel toggles while terminals live.

## Open Decisions

- None.

## References

- [DESIGN.md](DESIGN.md): design contract. Update the Sidebar section before code.
- [app/Atelier/Sources/Atelier/Workspace/Views/ContentView.swift](app/Atelier/Sources/Atelier/Workspace/Views/ContentView.swift): `WorkspaceSidebarTab` enum near line 15; sidebar tab strip near line 808; sidebar body switch near line 831.
- [app/Atelier/Sources/Atelier/Terminal/TerminalController.swift](app/Atelier/Sources/Atelier/Terminal/TerminalController.swift): wraps SwiftTerm terminal. Add a foreground-process accessor here.
- [app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift](app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift): `TerminalTabsModel`, `CenterTab`, `TerminalSession { id, title, controller }`.
- [app/Atelier/Sources/Atelier/Workspace/State/WorkspaceSession.swift](app/Atelier/Sources/Atelier/Workspace/State/WorkspaceSession.swift): per-workspace session owning `terminalTabs`.
- SwiftTerm facts: `LocalProcessTerminalView.process: LocalProcess`; `LocalProcess.childfd: Int32` is the master pty fd; `LocalProcess.shellPid: pid_t` is the child shell pid; `LocalProcess.running: Bool`. `childfd` becomes -1 after terminate, so guard it.
- Detection technique: `tcgetpgrp(childfd)` returns the foreground process group id. If it is invalid or equals `shellPid`, the terminal sits at the shell. Otherwise read the argv of that pid with `sysctl` `KERN_PROCARGS2` and match agent tokens.
- Default agent tokens: `claude`, `codex`, `aider`, `gemini`, `cursor-agent`. Keep them in one constant. A Settings control is a later phase.
- Phase 2, later: background live status, a badge on the tab or rail when an agent finishes while the panel is closed, exit codes through OSC 133, and a configurable agent list in Settings.
