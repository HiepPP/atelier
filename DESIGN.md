# Atelier Design System

## Document Status

| Field | Value |
|---|---|
| Status | Current implementation baseline |
| Updated | 2026-07-19 |
| Baseline commit | `02ebe5b` |
| Platform | macOS 26+ |
| UI stack | SwiftUI, AppKit, Luminare |

This file records and governs the current Atelier design. Update this contract before implementing behavior that changes it.

## Product Character

Atelier is a native macOS workspace tool. It should feel focused, dense, calm, and expensive.

- Use native macOS structure, behavior, menus, focus, and keyboard input.
- Keep the center editor as the main visual surface.
- Use an executive-alloy hierarchy: smoked graphite navigation, titanium chrome, porcelain work surfaces, and one terracotta accent.
- Use compact controls and clear hierarchy instead of decorative chrome.
- Show state through fill, weight, opacity, and thin rules.
- Keep the editor matte. Reserve glass and the signature gradient for navigation and compact chrome.
- Keep motion short and useful. Never block work with animation.
- Preserve text clarity at every display scale.

## Interface Architecture

SwiftUI owns composition and observable presentation state. AppKit owns native views and focus-sensitive behavior.

```text
AtelierApp
`-- ContentView
    |-- Workspace rail
    |   |-- Ordered live workspace rows
    |   `-- Add workspace action
    |-- Selected workspace content
    |   |-- Empty catalog
    |   `-- WorkspaceView
    |       |-- Toolbar
    |       |-- Native split controller
    |       |   |-- Sidebar: Explorer or Git
    |       |   |-- Center: terminal, file, diff, or Gemma tabs
    |       |   `-- Inspector
    |       `-- Status bar
    `-- Quick Open or Command Palette overlay
```

| Layer | Owns |
|---|---|
| SwiftUI | App shell, workspace catalog, active selection, layout, tabs, commands, settings, visible state |
| AppKit | File outline, editor, terminal, window focus, cursor, native tracking |
| Models | Ordered live sessions, tab lifecycle, navigation history, Git state, palette state, zoom state |
| Services | Catalog persistence, file loading, watching, Git, terminal processes, per-session workspace access |
| Theme bridge | Shared colors and native view chrome across SwiftUI and AppKit |

## Layout System

### Window and Modes

The minimum workspace size is `760 x 512` points.

The workspace rail stays at the outer-left edge in every mode. Its fixed width is included inside the minimum window size. Focus mode hides workspace side panels, but never hides the rail.

| Mode | Container width | Sidebar | Inspector |
|---|---:|---|---|
| Compact | `< 900` | Hidden | Hidden |
| Standard | `900..<1280` | Visible | Hidden |
| Wide | `>= 1280` | Visible | Visible |

Rules:

- Use one native `NSSplitViewController` with thin dividers.
- Keep split items mounted and use native item collapse for panel visibility.
- Animate sidebar collapse by changing its allocated split width, not view opacity.
- Keep panel transitions atomic through `WorkspacePanelPresentation`.
- Standard mode shows either sidebar or inspector, not both.
- Wide mode may keep sidebar and inspector visible together.
- Compact mode keeps the center surface only.
- Focus mode hides both side panels and restores their prior state on exit.
- Never rebuild this layout with dynamic `NavigationSplitView` and `.inspector` composition.
- Restore a saved responder only when it still belongs to the target window.

### Panel Widths

| Surface | Minimum | Ideal | Maximum |
|---|---:|---:|---:|
| Workspace rail | 176 | 176 | 176 |
| Workspace sidebar | 300 | 340 | 420 |
| Center | 420 | 660 | Flexible |
| Inspector | 220 | 260 | 320 |
| Explorer legacy range | 220 | 280 | 400 |
| Source Control legacy range | 320 | 380 | 540 |

### Fixed Heights

| Token | Value | Use |
|---|---:|---|
| `panelHeaderHeight` | 40 | Panel and diff headers |
| `sectionHeaderHeight` | 36 | Sidebar tabs and section headers |
| `tabBarHeight` | 34 | Center tab strip |
| `statusBarHeight` | 26 | Bottom workspace status |
| `fieldHeight` | 32 | Search and text fields |
| `controlHeight` | 28 | Regular controls |
| `compactControlHeight` | 24 | Inline and code controls |
| `rowHeight` | 28 | Dense list rows |
| `workspaceRailWidth` | 176 | Persistent labeled workspace rail |
| `workspaceRailItemHeight` | 44 | Two-line workspace row target |
| `workspaceRailItemGap` | 4 | Vertical space between workspace rows |
| `projectMenuWidth` | 420 | Principal project menu command-center width |

## Color Tokens

All palette colors are dynamic `sRGB` colors. Foreground text uses native label colors.

| Token | Light | Dark | Role |
|---|---|---|---|
| `chrome` | `#E7E3DD` | `#23262A` | Titanium toolbar, headers, status, tab strip |
| `canvas` | `#DEDAD3` | `#181A1D` | Window and empty-state background |
| `sidebar` | `#E1DED8` | `#202328` | Explorer and Git sidebar |
| `panel` | `#F2F0EC` | `#292C30` | Pearl inspector, cards, and panel content |
| `raised` | `#D4D0C9` | `#34383D` | Raised controls and palette body |
| `editor` | `#F8F7F4` | `#191B1E` | Matte porcelain editor, code, and terminal base |
| `tabInactive` | `#E5E1DB` | `#25282C` | Inactive tabs |
| `border` | `#BFBAB2` | `#42474D` | Dividers and control outlines |
| `selection` | `#DED1C6` | `#4B3730` | Selected rows and tabs |
| `hover` | `#D8D4CD` | `#383C41` | Hover state |
| `pressed` | `#CCC7BF` | `#44494F` | Pressed state |
| `accent` | `#A44F32` | `#D79570` | Primary emphasis and focus |
| `accentInk` | `#FFF9F2` | `#21150F` | Text on accent fill |
| `workspaceRailTop` | `#1D232B` | `#171C22` | Upper graphite rail gradient stop |
| `workspaceRailBottom` | `#2D3B45` | `#202D35` | Lower petrol rail gradient stop |
| `workspaceRailSolid` | `#252D35` | `#1D252C` | Reduce Transparency rail fallback |
| `workspaceRailForeground` | `#F3F1EC` | `#F3F1EC` | Primary text and icons on the rail |
| `workspaceRailSecondary` | `#B6BEC3` | `#ADB7BD` | Rail metadata and inactive icons |
| `workspaceRailSelection` | `#3B444C` | `#343E46` | Active rail row fill |
| `workspaceRailHover` | `#333C44` | `#2D373F` | Rail hover fill |
| `workspaceRailPressed` | `#46515A` | `#404B54` | Rail pressed fill |
| `workspaceRailBorder` | `#59636B` | `#4C575F` | Rail edge and focused control outline |
| `fileTreeForeground` | `#302E2B` | `#E8E4DE` | Stable Explorer label color, including selection |
| `gitAdded` | `#356B43` | `#7FC58C` | Additions and success |
| `gitModified` | `#8A5B21` | `#D4A45D` | Modified state |
| `gitDeleted` | `#A13E37` | `#E17B70` | Deletions, danger, destructive state |
| `gitUntracked` | `#286E68` | `#63C3B8` | Untracked state and code cyan |

Color rules:

- Reserve accent for selection, focus, primary action, and active indicators.
- Reserve Git colors for file and diff meaning.
- Use native primary and secondary labels for normal text.
- Use dedicated rail foreground tokens because the rail remains dark in both appearances.
- Do not create feature-local colors when an existing semantic token fits.
- Use one active accent per surface. Avoid competing highlights.

## Spacing and Shape Tokens

### Spacing

Atelier uses an 8-point grid with a 4-point half step.

| Token | Value |
|---|---:|
| `spaceXS` | 4 |
| `spaceS` | 8 |
| `spaceM` | 12 |
| `spaceL` | 16 |
| `spaceXL` | 24 |
| `space2XL` | 32 |

### Shape and Depth

| Token | Value | Use |
|---|---:|---|
| `panelRadius` | 12 | Floating panels and empty-state icon wells |
| `controlRadius` | 8 | Fields, buttons, cards, glass controls |
| `rowRadius` | 6 | Badges and compact row controls |
| `strokeHairline` | 0.5 | Panel separators |
| `strokeControl` | 0.75 | Control and card outlines |
| `strokeFocus` | 1.5 | Focus ring |
| `disabledOpacity` | 0.45 | Disabled actions |
| `inactiveOpacity` | 0.72 | Secondary inactive content |

Depth rules:

- Use borders before shadows for structure.
- Use `shadowSoft` only for raised local content.
- Use `shadowFloating` for modal overlays such as the palette.
- Use the `0.12` black scrim behind blocking overlays.
- Allow one signature gradient on the workspace rail and a restrained directional sheen on shared chrome.
- Keep editor, terminal, Explorer, Git, and inspector content matte and gradient-free.
- Do not add broad glow, deep drop shadows, or decorative glass layers.

## Typography

| Token | Size | Typical use |
|---|---:|---|
| `micro` | 11 | Shortcuts, metadata, compact badges |
| `caption` | 11 | Secondary labels and controls |
| `label` | 11.5 | Tabs and compact actions |
| `body` | 12.5 | Main UI copy |
| `uiSize` | 13 | Fields and standard interface text |
| `headline` | 15 | Panel headers |
| `title` | 17 | Section titles and strong empty states |
| `display` | 24 | Large empty-state titles |
| `editorSize` | 13 | Source editor |
| `terminalSize` | 14 | Terminal |

Type rules:

- Use the native system face for interface text.
- Use serif only for editorial headers and empty-state titles.
- Use monospaced text for paths, code, shortcuts, counts, and technical metadata.
- Prefer JetBrains Mono for code. Fall back to the system monospaced font.
- Use semibold for hierarchy. Avoid broad use of bold text.
- Snap scaled sizes to device pixels to keep text crisp.

## Display Sizing and Zoom

Display sizing sets a base scale. User zoom is applied on top.

| Tier | Physical diagonal | Base scale |
|---|---:|---:|
| Compact | `< 16 inches` | 1.00 |
| Comfortable | `16..<25 inches` | 1.10 |
| Large | `>= 25 inches` | 1.20 |

Rules:

- Fall back to Comfortable when display size is unavailable.
- Persist the sizing mode under `atelier.displaySizingMode`.
- Keep manual zoom between `0.8` and `2.0`, in `0.1` steps.
- Cap chrome scaling at `1.2` and sidebar scaling at `1.5`.
- Allow content to use the full render scale.
- Store manual zoom per display during the app session.
- Enter focus mode automatically when zoom exceeds the side-panel threshold.

## Motion

| Token | Value | Use |
|---|---:|---|
| `quick` | 0.12s | Hover and press feedback |
| `standard` | 0.20s | Normal transitions |
| `deliberate` | 0.32s | Larger state changes |
| `panel` | Smooth 0.32 / no bounce | Panel movement |
| `selection` | Spring 0.24 / 0.86 | Selection movement |

Motion rules:

- Disable optional motion when Reduce Motion is enabled.
- Use a short shine after refresh, shake for Git error, and small jump for a new terminal.
- Keep tab selection responsive with a short damped spring.
- Never animate loading in a way that changes layout size.

## Component Rules

### Shared Components

| Component | Contract |
|---|---|
| `AtelierPanelHeader` | One 40-point header, optional SF Symbol, mono subtitle, trailing controls |
| `AtelierEmptyState` | One calm icon well, serif title, short message, optional action |
| `AtelierToolbarButtonStyle` | 30-point target, glass state, accent underline when selected |
| `AtelierCountBadge` | Monospaced count with semantic tint |
| `AtelierGhostButtonStyle` | Quiet inline action with full hover, press, and disabled states |
| `AtelierFilledButtonStyle` | Primary action with accent fill and accent ink |
| `AtelierRowIconButtonStyle` | Compact row action with native pointer feedback |
| `atelierField` | Editor fill, 8-point radius, visible accent focus ring |
| `atelierCard` | Panel fill, continuous corners, thin semantic border |
| `atelierGlassControl` | Native glass when allowed, solid accessible fallback otherwise |

### Iconography

- Use SF Symbols for interface actions and status.
- Use one stable symbol for each typed action.
- Pair text with icons when the action is not obvious.
- Do not add decorative duplicate icons.
- Keep compact icon buttons at least 30 points.
- Give icon-only controls a help string and accessibility label.

### Interaction States

Every interactive control must define these states where relevant:

- Normal: clear fill and normal opacity.
- Hovered: semantic hover fill.
- Pressed: stronger pressed fill and a small scale change when motion is allowed.
- Selected: selection fill or accent indicator.
- Focused: accent-tinted fill and 1.5-point focus ring.
- Disabled: visible control with `0.45` opacity.

### Pointer Cursor

- Every enabled in-app control that performs an action on click must show the pointing-hand cursor across its full hit target.
- This rule includes buttons, menu triggers, tabs, selectable rows, toggles, pickers, shortcut recorders, and click-to-dismiss surfaces.
- Disabled controls must show the arrow cursor because they cannot perform their action.
- Text entry and selectable text keep the I-beam cursor. Splitters keep resize cursors. Drag-only surfaces keep their native drag cursor.
- System-owned window chrome, scroll bars, menu items, alerts, and sheets keep AppKit cursor behavior. Their in-app trigger still uses the pointing hand.
- SwiftUI controls use `atelierPointerCursor()`, preferably through their shared button style.
- AppKit controls use idempotent tracking areas or cursor rectangles that match the clickable region.
- Cursor and visual hover feedback must cover the same hit target.

## Surface Rules

### Workspace Chrome

- Use the unified compact macOS toolbar.
- Put sidebar toggle in navigation placement.
- Put project commands in the principal menu.
- Show the active project name in the menu and expose the full path as help text.
- Give the project menu a 420-point command-center width in the principal toolbar position.
- Keep the project identity centered, readable, and middle-truncated inside the full-width hit target.
- Keep the project command trigger text-only. Do not show a folder or disclosure icon.
- Preserve every existing project command in a 420-point top-anchored dropdown that matches the trigger width.
- Clicking any part of the project menu opens the existing project commands menu.
- Show the pointing-hand cursor across the full 420-point trigger.
- Keep the dropdown flush with the workspace content edge. Use a straight top edge with no callout arrow.
- Reveal the dropdown downward from its fixed top edge. Dismiss it by clipping the same surface upward into that edge.
- Keep project-menu motion reversible and bounce-free. Do not use whole-surface scale, blur, or fade-only transitions.
- Show and dismiss the dropdown without decorative reveal when Reduce Motion is enabled.
- Use a quiet native label inside the system toolbar material. Do not add a tinted icon tile, nested pill, glow, or heavy shadow.
- Put Gemma, focus mode, and inspector in primary actions.
- Keep branch, focus state, and zoom in the 26-point status bar.
- Use thin dividers between sidebar, center, inspector, and status bar.

### Workspace Rail

- Keep the rail outside `WorkspaceView`, its toolbar, split view, and status bar.
- Use a fixed 176-point rail with one hairline divider on its trailing edge.
- Show full project names as primary identity. Never use initials or monograms as primary identity.
- Show an abbreviated parent path below every project name in monospaced secondary text.
- Use the parent path to disambiguate duplicate project names.
- Place 44-point workspace rows in one vertical column with 4-point gaps and 8-point horizontal insets.
- Put one labeled `Add Workspace` action below the scrollable workspace list.
- Support drag-and-drop reordering within the rail and persist the new order.
- Give every workspace row a native context menu for activation, Finder, path copy, ordering, and close.
- A context-menu close targets that item. It must not switch or close the active workspace first.
- Mark the active workspace with label weight, restrained selection fill, a checkmark, and a 2-point leading accent rule.
- Show loading, unavailable, and error accessories without replacing project identity.
- Show the full path in help and accessibility text.
- Use rail-specific hover, pressed, focused, selected, and disabled fills so contrast stays stable.
- Keep optional motion limited to quick opacity and scale feedback. Disable it under Reduce Motion.
- Keep the rail dark in light and dark appearance. Use the graphite-to-petrol gradient as its only signature depth effect.
- Use `workspaceRailSolid` when Reduce Transparency is enabled.
- Use a faint top-edge sheen and one trailing hairline. Do not add glow, heavy shadows, pills, or dock magnification.

Workspace item states:

| State | Visual treatment | Interaction | Accessibility value |
|---|---|---|---|
| Active | Semibold name, secondary path, selection fill, checkmark, leading rule | Selecting again keeps current session | `Selected, available` |
| Inactive | Primary name, secondary path, clear fill | Selects existing live session | `Available` |
| Loading | Secondary name and path, native progress indicator | Disabled until restore finishes | `Loading` |
| Unavailable | Primary name, secondary path, `questionmark.folder` accessory | Selects item and presents recovery context | `Unavailable` |
| Error | Primary name, secondary path, semantic error accessory | Selects item and presents error context | `Error` |
| Disabled | Clear fill at disabled opacity | No action | `Disabled` |

Catalog states:

- Empty: keep the rail and add action visible. Show the existing open-folder empty state in the content area.
- Partial restore: restore every saved item independently. One missing folder never blocks valid sessions.
- No active item: show the empty content state while preserving unavailable catalog items.
- Switching: change active selection only. Keep inactive sessions, terminals, watchers, Git models, agents, palettes, tabs, and navigation alive.
- Duplicate selection: activate the existing item for the standardized path. Never create a second live session.
- Close: release only the closed session, then select the next item, previous item, or empty state in that order.
- Quit: stop every session and release every security-scoped resource.

Persistence boundaries:

- Persist ordered workspace identity, standardized path, bookmark data, and selected workspace identity as one app-level catalog.
- Decode the legacy single `WorkspaceState` payload as a one-item catalog without user action.
- Keep tabs, terminals, preview state, navigation, Git presentation, agents, palettes, and responders session-only.
- Each live `WorkspaceSession` owns independent security-scoped access for its full lifetime.
- Never restore a saved AppKit responder unless it belongs to the active session and target window.

### Sidebar

- Use the warm titanium sidebar token. Keep its content matte and slightly darker than the editor.
- Use the chrome sheen only on the 40-point sidebar header.
- Explorer and Git share one sidebar slot.
- Keep the sidebar header visually limited to the Explorer and Git tabs. Do not place actions inside or after the tabs.
- Put a compact contextual toolbar at the top of the selected tab body, directly below the tab bar.
- Right-align New File and New Folder in the Explorer toolbar. Right-align Refresh in the Git toolbar.
- Render only the selected body's actions. Keep the tab label, count, selection target, help, and accessibility text intact.
- The selected sidebar tab uses selection fill and a 2-point accent underline.
- Show the Git change count as a semantic badge.
- Keep body toolbar actions at 24 points, with quiet hover and pressed fills.
- Keep selected file labels in the primary text color. Use selection fill, a thin accent edge, and no inverted text.
- Vertically center the disclosure, icon, and label within every file-tree row.
- Keep the base file or folder icon and add an `arrow.turn.up.right` badge after symlink names.
- Do not expand directory symlinks from Explorer.
- Explorer single-click opens one replaceable preview.
- Explorer double-click opens or promotes a permanent tab.
- Quick Open and every non-Explorer route open permanent tabs.

### Center Tabs

- Use titanium chrome for the strip and porcelain for the selected editor surface.
- Keep Back and Forward visible before the horizontal tab scroller.
- Keep tab widths between 112 and 220 points, with 152 ideal.
- Mark selection with primary text and a 2-point accent top rule.
- Mark preview with regular label weight and `0.72` opacity. Do not add another icon.
- Place the close control at the left edge of every closable tab.
- Show close only on the selected or hovered tab.
- Preserve drag reorder, rename, context menu, and word-wrap behavior.
- Keep terminal response and new-terminal actions after the scroller.
- Reopen Closed Tab restores permanent file tabs only.

### Quick Open and Command Palette

- Use one shared floating panel for both modes.
- Keep the panel at 640 points maximum width and 410 points height.
- Use editor fill for the 52-point query field.
- Use raised fill for results and chrome fill for the keyboard footer.
- Show file name first and a monospaced relative path second.
- Show command title, category, shortcut, and live availability.
- Support Up, Down, Return, Escape, and double-click.
- `Cmd-P` opens Quick Open. `Cmd-Shift-P` opens the Command Palette.

### Git

- Keep repository, branch, summary, commit input, and change groups in the sidebar.
- Open file diffs as center tabs, not inside the Git sidebar.
- Use semantic green, orange, red, and teal only for Git meaning.
- Keep diff line numbers in a fixed 48-point gutter.
- Use monospaced selectable diff text.
- Confirm destructive discard actions with a native alert.

### Editor and Terminal

- Keep the center work surface the brightest large region. It must remain matte, quiet, and highly legible.
- Keep code gutters and terminal backgrounds aligned with the editor token.
- Use the editor surface color for source, diff, and terminal content.
- Use native AppKit text and terminal views through narrow representable bridges.
- Keep editor word wrap as a per-file setting.
- Promote a preview before the first edit is saved.
- Preserve first responder across palette, zoom, inspector, and sidecar transitions.

### Gemma and Agent Responses

- Use a readable transcript width capped at 680 points.
- Keep user and assistant hierarchy clear without chat-bubble decoration everywhere.
- Use cards for tool activity and structured results.
- Present terminal responses as a sidecar controlled from the tab bar.
- Keep status, navigation, refresh, copy, and close actions keyboard accessible.

### Settings

- Use a fixed 460-point width and at least 400 points height.
- Group settings into flat sections separated by hairlines.
- Use serif section titles with accent color.
- Keep explanations short and secondary.
- Use native Picker, Toggle, and shortcut recorder controls.

## Keyboard Rules

| Shortcut | Action |
|---|---|
| `Cmd-O` | Open Folder |
| `Cmd-T` | New Terminal |
| `Cmd-P` | Quick Open |
| `Cmd-Shift-P` | Command Palette |
| `Ctrl--` | Back |
| `Ctrl-Shift--` | Forward |
| `Cmd-Shift-T` | Reopen Closed Tab |
| `Cmd-+` | Zoom In |
| `Cmd--` | Zoom Out |
| `Cmd-0` | Actual Size |
| `Cmd-Shift-F` | Toggle Focus Mode |
| `Option-Z` | Toggle Word Wrap |

Rules:

- Menu items, palette actions, and toolbar controls must call the same typed action.
- Show live enabled state in every action surface.
- Do not reuse an existing shortcut for a new action.
- Keep shortcut labels monospaced in the command palette.

## Accessibility Rules

- Give every icon-only control a label and help text.
- Expose selected, preview, available, unavailable, loading, and unread states as values.
- Use native primary and secondary label colors for system contrast support.
- Replace glass with solid fills when Reduce Transparency is enabled.
- Increase selected glass borders when Increase Contrast is enabled.
- Disable optional motion when Reduce Motion is enabled.
- Keep keyboard focus stable after overlays and panel transitions.
- Keep keyboard focus within the active session after workspace switching. Reject responders from inactive sessions.
- Keep narrow layouts usable without hiding core tab navigation.

## Implementation Rules

- Use existing tokens before adding literals.
- Add shared semantic tokens only in the Theme layer.
- Keep SwiftUI and AppKit colors aligned through `AppKitThemeAdapter`.
- Prefer native SwiftUI and AppKit controls before custom drawing.
- Keep AppKit customization defensive and idempotent.
- Keep view modifiers small and named by visual contract.
- Do not add a component for one local use.
- Do not add gradients beyond the rail, shared chrome sheen, and existing small empty-state illustrations.
- Do not add heavy shadows or large rounded cards to dense workspace surfaces.
- Do not use web dashboard patterns, oversized hero copy, or floating card grids.
- Do not change panel visibility in several async steps.
- Do not restore an AppKit responder from another window.
- Route global actions through `AtelierActionRegistry`.
- Resolve workspace-scoped actions against the active session at invocation time.
- Keep the workspace catalog on `MainActor`. Do not share workspace-owned model instances between sessions.
- Keep preview state session-only. Keep navigation history session-only.

## Verification Rules

Every UI change must pass deterministic and native checks.

```bash
swift build --package-path app/Atelier
swift test --package-path app/Atelier
app/Atelier/.build/debug/Atelier --selftest
app/Atelier/scripts/build_and_run.sh run
```

Native checks:

- Test narrow layout at exactly `760 x 512`.
- Test wide layout at exactly `1440 x 900`.
- Test duplicate project names and confirm rail parent paths disambiguate them.
- Test one long project name and confirm the rail and project menu preserve readable identity.
- Test the rail with Explorer and Inspector hidden.
- Check light and dark appearance when colors change.
- Check keyboard focus after opening and closing overlays.
- Open and close the project menu with pointer and keyboard.
- Check Reduce Motion and Reduce Transparency when effects change.
- Switch between two workspaces ten times and confirm tabs and terminals remain isolated and alive.
- Reorder three workspaces, relaunch, and confirm the order persists.
- Close an inactive workspace from its context menu and confirm the active session stays selected.
- Select the same standardized folder twice and confirm the existing session activates.
- Restore one valid and one missing workspace and confirm the valid workspace remains usable.
- Stress sidebar, inspector, preview, and window-size transitions.
- Hover every visible clickable control and confirm the pointing hand covers its full hit target.
- Confirm disabled controls use the arrow while text, resize, and drag surfaces keep their semantic cursors.
- Treat AppKit constraint-loop and detached-responder warnings as failures.
- Store screenshots outside tracked paths unless a task requests fixtures.

## Source of Truth

| Area | Source |
|---|---|
| Product and architecture | [README.md](README.md) |
| App shell and zoom | [AtelierApp.swift](app/Atelier/Sources/Atelier/App/AtelierApp.swift) |
| Colors, metrics, typography | [AtelierTheme.swift](app/Atelier/Sources/Atelier/Theme/AtelierTheme.swift) |
| Native color values | [AppKitThemeAdapter.swift](app/Atelier/Sources/Atelier/Theme/AppKitThemeAdapter.swift) |
| Shared components | [AtelierComponents.swift](app/Atelier/Sources/Atelier/Theme/AtelierComponents.swift) |
| Luminare styles | [AtelierLuminareStyle.swift](app/Atelier/Sources/Atelier/Theme/AtelierLuminareStyle.swift) |
| Motion | [AtelierMotion.swift](app/Atelier/Sources/Atelier/Theme/AtelierMotion.swift) |
| Display sizing | [DisplaySizing.swift](app/Atelier/Sources/Atelier/Theme/DisplaySizing.swift) |
| Workspace layout | [ContentView.swift](app/Atelier/Sources/Atelier/Workspace/Views/ContentView.swift) |
| Center tabs | [TerminalTabs.swift](app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift) |
| Palette | [AtelierPaletteView.swift](app/Atelier/Sources/Atelier/Commands/AtelierPaletteView.swift) |
| Action catalog | [AtelierActionRegistry.swift](app/Atelier/Sources/Atelier/Commands/AtelierActionRegistry.swift) |
| Settings | [AtelierSettingsView.swift](app/Atelier/Sources/Atelier/Settings/AtelierSettingsView.swift) |

Update this document when a shared token, breakpoint, component contract, or design rule changes.
