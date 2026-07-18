# TASK-004 Add Navigation Actions and Native Chrome

Group: C (complete native navigation slice)

## Brief

Goal: Expose Back, Forward, and Reopen Closed Tab through the action registry, menus, command palette, shortcuts, and native tab chrome.

Change: Hidden navigation state -> visible keyboard-first navigation controls with live availability.

How:

- Add stable action IDs and descriptors for Back, Forward, and Reopen Closed Tab.
- Add live action context values and handlers backed by `TerminalTabsModel`.
- Bind Control-minus to Back and Control-Shift-minus to Forward.
- Bind Command-Shift-T to Reopen Closed Tab.
- Keep Command-minus for Zoom Out, Command-P for Quick Open, and Command-Shift-P for the command palette.
- Add small Back and Forward buttons before the horizontal tab scroller.
- Keep disabled buttons visible and expose clear labels, help, and availability.
- Give preview tab titles subtle text styling and an accessibility value without another icon.
- Preserve tab reordering, hover close buttons, rename, word wrap, and response controls.
- Update action registry and palette tests for stable order, availability, and dispatch.
- Run native narrow and wide checks with exact behavior evidence and screenshots.

Files:

- [app/Atelier/Sources/Atelier/Commands/AtelierActionRegistry.swift](app/Atelier/Sources/Atelier/Commands/AtelierActionRegistry.swift) (navigation descriptors, context, handlers, and dispatch)
- [app/Atelier/Sources/Atelier/App/AppCommands.swift](app/Atelier/Sources/Atelier/App/AppCommands.swift) (menu commands and default shortcuts)
- [app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift](app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift) (tab-bar buttons, preview styling, accessibility, and model actions)
- [app/Atelier/Tests/AtelierTests/AtelierActionRegistryTests.swift](app/Atelier/Tests/AtelierTests/AtelierActionRegistryTests.swift) (catalog, availability, and handler routing)
- [app/Atelier/Tests/AtelierTests/AtelierPalettePresentationTests.swift](app/Atelier/Tests/AtelierTests/AtelierPalettePresentationTests.swift) (command palette visibility and live enabled state)
- [app/Atelier/Tests/AtelierTests/TerminalTabsNavigationTests.swift](app/Atelier/Tests/AtelierTests/TerminalTabsNavigationTests.swift) (action integration and preview presentation state)

Expected result:

- Menus and the command palette expose all three navigation actions.
- Shortcuts run the same typed dispatcher as menus and the command palette.
- Back and Forward buttons reflect live history availability.
- Reopen Closed Tab is enabled only when a permanent closed file exists.
- Preview tabs are visually distinct without adding icon noise.
- The tab bar remains usable at narrow and wide window sizes.

Prompt:

```text
Complete the native navigation slice described in this TASK. Route Back, Forward, and Reopen Closed Tab through AtelierActionRegistry. Add small leading tab-bar buttons, subtle preview text styling, deterministic action tests, and native checks at 760 x 512 and 1440 x 900. Do not add pinned tabs, custom keymaps, or persistent history.
```

## Verify

- `swift test --package-path app/Atelier --filter AtelierActionRegistryTests` -> catalog, availability, and dispatch tests pass.
- `swift test --package-path app/Atelier --filter AtelierPalettePresentationTests` -> navigation actions appear with current enabled state.
- `swift test --package-path app/Atelier --filter TerminalTabsNavigationTests` -> navigation action integration and preview state tests pass.
- At 760 x 512, Back and Forward remain visible while the tab list scrolls without clipping trailing controls.
- At 1440 x 900, single-click preview, edit promotion, Back, Forward, and Reopen Closed Tab all work.
- Control-minus, Control-Shift-minus, and Command-Shift-T match their menu actions.
- VoiceOver labels identify Back, Forward, preview tab state, and Reopen Closed Tab availability.
- Store narrow and wide screenshots outside tracked paths and record their paths in the outcome sidecar.
- `swift build --package-path app/Atelier` -> build succeeds.
- `swift test --package-path app/Atelier` -> full suite passes.
- `app/Atelier/.build/debug/Atelier --selftest` -> packaged checks pass.
- `app/Atelier/scripts/build_and_run.sh run` -> Atelier builds, signs, installs, and launches.
