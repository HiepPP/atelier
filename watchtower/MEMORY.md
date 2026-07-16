# Watchtower Memory

## Purpose

Read this file before creating or implementing Watchtower tasks in this repo.

This file holds long-term intent. It keeps task planning aligned across sessions.

## Core Intent

- Atelier is a native macOS workspace with Explorer, Terminal, and Git columns.
- The warm VS Code palette and three-column layout must remain stable.

## Planning Rules

- Add UI libraries only through small app-owned adapters.
- Keep model actions, keyboard shortcuts, menus, and dialogs unchanged during visual work.
- Do not replace the app shell with a library window, pane, sidebar, or material system.
- Use `rg` for source search. Do not use GitNexus in this repository.

## Source Anchors

- [app/Atelier/Sources/Atelier/ContentView.swift](../app/Atelier/Sources/Atelier/ContentView.swift): three-column shell and status bar.
- [app/Atelier/Sources/Atelier/AtelierTheme.swift](../app/Atelier/Sources/Atelier/AtelierTheme.swift): palette, button styles, and AppKit chrome.
- [app/Atelier/Sources/Atelier/ChangesView.swift](../app/Atelier/Sources/Atelier/ChangesView.swift): Git inspector, status states, and destructive dialog.
- [app/Atelier/Package.swift](../app/Atelier/Package.swift): package compatibility contract.

## Verification Bias

- `swift build --package-path app/Atelier`
- `app/Atelier/.build/debug/Atelier --selftest`
- Native GUI checks at minimum and wide window sizes.

## Avoid

- Do not trade exact palette control for translucent library defaults.
- Do not downgrade SwiftUI-Introspect to make another package resolve.
- Do not add dormant popovers or inspector panels without a real product action.

## Learnings

### 2026-07-16 - Luminare dependency gate

- Learned: Luminare `0.2.0` requests SwiftUI-Introspect `1.x`, while Atelier pins `26.0.1`.
- Source: [app/Atelier/Package.swift](../app/Atelier/Package.swift)
- Use next time: prove dependency compatibility before changing production UI files.

### 2026-07-16 - Luminare adapter contract

- Learned: upstream `.luminareProminent` uses a weak tint fill that drifts from Atelier's solid accent.
- Source: [app/Atelier/Sources/Atelier/AtelierLuminareStyle.swift](../app/Atelier/Sources/Atelier/AtelierLuminareStyle.swift)
- Use next time: keep Luminare interaction modifiers, but own palette fills and disabled opacity in the adapter.
