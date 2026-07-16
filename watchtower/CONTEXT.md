# Plan Context

## Shared Context

- Atelier is a macOS 13 SwiftUI app with Explorer, Terminal, and Git columns.
- The layout contract lives in [app/Atelier/Sources/Atelier/ContentView.swift](../app/Atelier/Sources/Atelier/ContentView.swift).
- Palette and AppKit chrome live in [app/Atelier/Sources/Atelier/AtelierTheme.swift](../app/Atelier/Sources/Atelier/AtelierTheme.swift).
- Current button actions live in [app/Atelier/Sources/Atelier/ContentView.swift](../app/Atelier/Sources/Atelier/ContentView.swift), [app/Atelier/Sources/Atelier/ChangesView.swift](../app/Atelier/Sources/Atelier/ChangesView.swift), and [app/Atelier/Sources/Atelier/TerminalTabs.swift](../app/Atelier/Sources/Atelier/TerminalTabs.swift).
- The right Git column is the inspector surface. Its `VSplitView` must remain unchanged.

## Audit Findings

- [app/Atelier/Package.swift](../app/Atelier/Package.swift) pins SwiftUI-Introspect `26.0.1`.
- Luminare `0.2.0` supports macOS 13 but requests SwiftUI-Introspect from `1.0.0`.
- Those package ranges conflict. A compatibility spike must pass before app integration.
- Luminare button styles and `LuminareSection` fit the requested narrow scope.
- `LuminareWindow`, `LuminarePane`, and `luminareBackground` would replace current chrome or material.
- Atelier has no production popover. Do not add a new trigger only to demonstrate Luminare.
- Keep [app/Atelier/Sources/Atelier/BranchControl.swift](../app/Atelier/Sources/Atelier/BranchControl.swift) as a native `Menu`.
- Keep the discard `confirmationDialog` in [app/Atelier/Sources/Atelier/ChangesView.swift](../app/Atelier/Sources/Atelier/ChangesView.swift).

## Decisions

- Keep every value in `AtelierNativePalette` and `AtelierTheme` as the visual source of truth.
- Use Luminare through app-owned adapters. Do not spread `import Luminare` across feature views.
- Use no translucent material, new column, new command, or new state.
- Use `rg` for source search. Do not use GitNexus in this repository.

## Open Decisions

- TASK-001 must select a compatible package source. Ask before creating any remote fork.

## References

- [Luminare repository](https://github.com/MrKai77/Luminare)
- [app/Atelier/Package.swift](../app/Atelier/Package.swift)
- [app/Atelier/Sources/Atelier/AtelierTheme.swift](../app/Atelier/Sources/Atelier/AtelierTheme.swift)
- [app/Atelier/Sources/Atelier/ChangesView.swift](../app/Atelier/Sources/Atelier/ChangesView.swift)
