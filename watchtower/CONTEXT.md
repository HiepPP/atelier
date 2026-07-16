# Plan Context

## Shared Context

- Atelier is a macOS 13 SwiftUI app with Explorer, Terminal, and Git columns.
- The layout contract lives in [app/Atelier/Sources/Atelier/ContentView.swift](../app/Atelier/Sources/Atelier/ContentView.swift).
- Palette and AppKit chrome live in [app/Atelier/Sources/Atelier/AtelierTheme.swift](../app/Atelier/Sources/Atelier/AtelierTheme.swift).
- Current button actions live in [app/Atelier/Sources/Atelier/ContentView.swift](../app/Atelier/Sources/Atelier/ContentView.swift), [app/Atelier/Sources/Atelier/ChangesView.swift](../app/Atelier/Sources/Atelier/ChangesView.swift), and [app/Atelier/Sources/Atelier/TerminalTabs.swift](../app/Atelier/Sources/Atelier/TerminalTabs.swift).
- Read-only file and diff text lives in [app/Atelier/Sources/Atelier/FileViewer.swift](../app/Atelier/Sources/Atelier/FileViewer.swift).
- The app scene and self-test live in [app/Atelier/Sources/Atelier/AtelierApp.swift](../app/Atelier/Sources/Atelier/AtelierApp.swift).
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
- SwiftUIX `0.3.1` supports macOS 11 and requires Swift tools 5.10.
- KeyboardShortcuts `3.0.1` supports macOS 10.15 and requires Swift tools 6.2.
- Pow `1.0.5` supports macOS 12 and requires Swift tools 5.7.
- The local toolchain is Swift `6.2.3` with Xcode `26.2`.

## Decisions

- Keep every value in `AtelierNativePalette` and `AtelierTheme` as the visual source of truth.
- Use Luminare through app-owned adapters. Do not spread `import Luminare` across feature views.
- Use no translucent material, new column, or speculative product state.
- Apply SwiftUIX only to the existing read-only file and diff viewer.
- Apply KeyboardShortcuts to one user-chosen global shortcut that raises Atelier.
- Apply Pow only to refresh completion, Git errors, and new terminal feedback.
- Disable Pow effects when Reduce Motion is enabled.
- Use `rg` for source search. Do not use GitNexus in this repository.

## Open Decisions

- None.

## References

- [Luminare repository](https://github.com/MrKai77/Luminare)
- [SwiftUIX repository](https://github.com/SwiftUIX/SwiftUIX)
- [KeyboardShortcuts repository](https://github.com/sindresorhus/KeyboardShortcuts)
- [Pow repository](https://github.com/EmergeTools/Pow)
- [app/Atelier/Package.swift](../app/Atelier/Package.swift)
- [app/Atelier/Sources/Atelier/AtelierTheme.swift](../app/Atelier/Sources/Atelier/AtelierTheme.swift)
- [app/Atelier/Sources/Atelier/ChangesView.swift](../app/Atelier/Sources/Atelier/ChangesView.swift)
