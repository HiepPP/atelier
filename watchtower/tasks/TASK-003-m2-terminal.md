# TASK-003 M2 embedded multi-tab terminal

Group: M2 (terminal milestone, ships on its own)

## Brief

Goal: Embed a multi-tab terminal in the app. Each tab runs the user shell at the workspace root.

Change: no terminal in app -> a terminal panel with add, close, and switch tabs.

How:

- Add SwiftTerm 1.14.0 as a dependency of [app/Atelier/Package.swift](app/Atelier/Package.swift).
- Wrap LocalProcessTerminalView in NSViewRepresentable. Reuse the spike pattern in [spike/swiftterm-spike/Sources/SwiftTermSpike/main.swift](spike/swiftterm-spike/Sources/SwiftTermSpike/main.swift).
- Start each tab with $SHELL as a login shell. Set cwd to the workspace path.
- Add a tab model and a tab bar: add, close, switch. Keep each tab alive when the panel loses focus.
- Do not parse terminal output to guess state.

Files:

- [app/Atelier/Package.swift](app/Atelier/Package.swift) (add SwiftTerm dependency)
- [app/Atelier/Sources/Atelier/TerminalView.swift](app/Atelier/Sources/Atelier/TerminalView.swift) (LocalProcessTerminalView wrapper)
- [app/Atelier/Sources/Atelier/TerminalTabs.swift](app/Atelier/Sources/Atelier/TerminalTabs.swift) (tab model and tab bar)
- [app/Atelier/Sources/Atelier/ContentView.swift](app/Atelier/Sources/Atelier/ContentView.swift) (add terminal panel to WorkspaceView)

Expected result:

- A terminal tab spawns the shell at the workspace root.
- Opening a second tab gives an independent shell.
- Closing a tab ends only that shell. Other tabs stay alive.
- Resizing the panel reflows the terminal.

## Verify

- cd app/Atelier && swift build -> ok (build complete).
- Launch app, open a workspace, open a terminal tab, run pwd -> prints the workspace path.
- Open a second tab, run a command, close the first tab -> second tab keeps working.
