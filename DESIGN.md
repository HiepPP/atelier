# Atelier Design System

## Document Status

| Field | Value |
|---|---|
| Status | Current implementation baseline |
| Updated | 2026-07-18 |
| Baseline commit | `72fcd61` |
| Platform | macOS 26+ |
| UI stack | SwiftUI, AppKit, Luminare |

This file records and governs the current Atelier design. Update this contract before implementing behavior that changes it.

## Product Character

Atelier is a native macOS workspace tool. It should feel focused, dense, warm, and calm.

- Use native macOS structure, behavior, menus, focus, and keyboard input.
- Keep the center editor as the main visual surface.
- Use a warm neutral palette with one terracotta accent.
- Use compact controls and clear hierarchy instead of decorative chrome.
- Show state through fill, weight, opacity, and thin rules.
- Keep motion short and useful. Never block work with animation.
- Preserve text clarity at every display scale.

## Interface Architecture

SwiftUI owns composition and observable presentation state. AppKit owns native views and focus-sensitive behavior.

```text
AtelierApp
`-- ContentView
    |-- Empty workspace
    |-- Quick Open or Command Palette overlay
    `-- WorkspaceView
        |-- Toolbar
        |-- HSplitView
        |   |-- Sidebar: Explorer or Git
        |   |-- Center: terminal, file, diff, or Gemma tabs
        |   `-- Inspector
        `-- Status bar
```

| Layer | Owns |
|---|---|
| SwiftUI | App shell, workspace layout, tabs, commands, settings, visible state |
| AppKit | File outline, editor, terminal, window focus, cursor, native tracking |
| Models | Tab lifecycle, navigation history, Git state, palette state, zoom state |
| Services | File loading, watching, persistence, Git, terminal processes, workspace access |
| Theme bridge | Shared colors and native view chrome across SwiftUI and AppKit |

## Layout System

### Window and Modes

The minimum workspace size is `760 x 512` points.

| Mode | Container width | Sidebar | Inspector |
|---|---:|---|---|
| Compact | `< 900` | Hidden | Hidden |
| Standard | `900..<1280` | Visible | Hidden |
| Wide | `>= 1280` | Visible | Visible |

Rules:

- Use native `HSplitView` with thin dividers.
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

## Color Tokens

All palette colors are dynamic `sRGB` colors. Foreground text uses native label colors.

| Token | Light | Dark | Role |
|---|---|---|---|
| `chrome` | `#F1EDE5` | `#23211F` | Toolbar, headers, status, tab strip |
| `canvas` | `#F6F2EA` | `#191816` | Window and empty-state background |
| `sidebar` | `#ECE7DE` | `#211F1C` | Explorer and Git sidebar |
| `panel` | `#FCFAF5` | `#292622` | Cards and panel content |
| `raised` | `#E2DCD1` | `#332F2A` | Raised controls and palette body |
| `editor` | `#FBFAF7` | `#1A1917` | Editor, code, and terminal base |
| `tabInactive` | `#ECE7DE` | `#24211E` | Inactive tabs |
| `border` | `#CDC5B8` | `#403B35` | Dividers and control outlines |
| `selection` | `#E8D4C2` | `#4C352A` | Selected rows and tabs |
| `hover` | `#E2DCD1` | `#37322D` | Hover state |
| `pressed` | `#D8D0C3` | `#423B34` | Pressed state |
| `accent` | `#935A3D` | `#D39A72` | Primary emphasis and focus |
| `accentInk` | `#FFF9F2` | `#21150F` | Text on accent fill |
| `gitAdded` | `#356B43` | `#7FC58C` | Additions and success |
| `gitModified` | `#8A5B21` | `#D4A45D` | Modified state |
| `gitDeleted` | `#A13E37` | `#E17B70` | Deletions, danger, destructive state |
| `gitUntracked` | `#286E68` | `#63C3B8` | Untracked state and code cyan |

Color rules:

- Reserve accent for selection, focus, primary action, and active indicators.
- Reserve Git colors for file and diff meaning.
- Use native primary and secondary labels for normal text.
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
- Do not add gradients except for small empty-state illustrations.

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
| `panel` | Spring 0.30 / 0.88 | Panel movement |
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

## Surface Rules

### Workspace Chrome

- Use the unified compact macOS toolbar.
- Put sidebar toggle in navigation placement.
- Put project commands in the principal menu.
- Put Gemma, focus mode, and inspector in primary actions.
- Keep branch, focus state, and zoom in the 26-point status bar.
- Use thin dividers between sidebar, center, inspector, and status bar.

### Sidebar

- Explorer and Git share one sidebar slot.
- The selected sidebar tab uses selection fill and a 2-point accent underline.
- Show the Git change count as a semantic badge.
- Keep file creation and refresh actions in the 40-point sidebar header.
- Vertically center the disclosure, icon, and label within every file-tree row.
- Keep the base file or folder icon and add an `arrow.turn.up.right` badge after symlink names.
- Do not expand directory symlinks from Explorer.
- Explorer single-click opens one replaceable preview.
- Explorer double-click opens or promotes a permanent tab.
- Quick Open and every non-Explorer route open permanent tabs.

### Center Tabs

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
- Keep narrow layouts usable without hiding core tab navigation.

## Implementation Rules

- Use existing tokens before adding literals.
- Add shared semantic tokens only in the Theme layer.
- Keep SwiftUI and AppKit colors aligned through `AppKitThemeAdapter`.
- Prefer native SwiftUI and AppKit controls before custom drawing.
- Keep AppKit customization defensive and idempotent.
- Keep view modifiers small and named by visual contract.
- Do not add a component for one local use.
- Do not add gradients, heavy shadows, or large rounded cards to dense workspace surfaces.
- Do not use web dashboard patterns, oversized hero copy, or floating card grids.
- Do not change panel visibility in several async steps.
- Do not restore an AppKit responder from another window.
- Route global actions through `AtelierActionRegistry`.
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
- Check light and dark appearance when colors change.
- Check keyboard focus after opening and closing overlays.
- Check Reduce Motion and Reduce Transparency when effects change.
- Stress sidebar, inspector, preview, and window-size transitions.
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
