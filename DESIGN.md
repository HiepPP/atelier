# Atelier Design System

## Document Status

| Field | Value |
|---|---|
| Status | Current implementation baseline |
| Updated | 2026-07-24 |
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
- Keep the editor matte. Reserve glass for navigation, compact chrome, and selected interactive
  surfaces only.
- Keep motion short and useful. Never block work with animation.
- Preserve text clarity at every display scale.

## Interface Architecture

SwiftUI owns composition and observable presentation state. AppKit owns native views and focus-sensitive behavior.

```text
AtelierApp
`-- ContentView
    |-- Workspace rail
    |   |-- Ordered live workspace groups
    |   |   |-- Workspace header
    |   |   `-- Nested live agent threads
    |   `-- Add Workspace
    |-- Selected workspace content
    |   |-- Empty catalog
    |   `-- WorkspaceView
    |       |-- Toolbar
    |       |-- Native split controller
    |       |   |-- Sidebar: Explorer or Git
    |       |   |-- Center: terminal, file, diff, or Gemma tabs
    |       |   `-- Inspector: Gemma sidecar assistant
    |       `-- Status bar
    `-- Quick Open or Command Palette overlay
```

| Layer | Owns |
|---|---|
| SwiftUI | App shell, workspace catalog, active selection, layout, tabs, commands, settings, visible state |
| AppKit | File outline, editor, terminal, window focus, cursor, native tracking |
| Models | Ordered live sessions, tab lifecycle, navigation history, Git state, palette state, zoom state |
| Services | Catalog and session persistence, file loading, watching, Git, terminal processes, per-session workspace access |
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
- Animate sidebar and inspector collapse by changing allocated split width, not opacity.
- Let the user drag the sidebar and inspector dividers to resize each pane within its width range; both open at their Ideal width.
- Animate only the panel explicitly toggled. Keep companion policy changes atomic.
- Keep side-panel holding priority above center so center absorbs reclaimed width.
- Keep panel transitions atomic through `WorkspacePanelPresentation`.
- Standard mode shows either sidebar or inspector, not both.
- Wide mode may keep sidebar and inspector visible together.
- Compact mode keeps the center surface only.
- The focus control is the master side-panel visibility control. It hides every panel together
  and restores the current layout's complete default panel set instead of a partial snapshot.
- Never rebuild this layout with dynamic `NavigationSplitView` and `.inspector` composition.
- Restore a saved responder only when it still belongs to the target window.

### Panel Widths

| Surface | Minimum | Ideal | Maximum |
|---|---:|---:|---:|
| Workspace rail | 176 | 176 | 176 |
| Workspace sidebar | 240 | 340 | 560 |
| Center | 420 | 660 | Flexible |
| Inspector | 260 | 360 | 640 |
| Agent response overlay | 50% of center | 100% of center | 100% of center |
| Explorer legacy range | 220 | 280 | 400 |
| Source Control legacy range | 320 | 380 | 540 |

### Fixed Heights

| Token | Value | Use |
|---|---:|---|
| `panelHeaderHeight` | 40 | Panel and diff headers |
| `sectionHeaderHeight` | 36 | Section headers below panel chrome |
| `tabBarHeight` | 40 | Center tab strip |
| `statusBarHeight` | 26 | Bottom workspace status |
| `fieldHeight` | 32 | Search and text fields |
| `controlHeight` | 28 | Regular controls |
| `compactControlHeight` | 24 | Inline and code controls |
| `rowHeight` | 28 | Dense list rows |
| `workspaceRailWidth` | 176 | Persistent labeled workspace rail |
| `workspaceRailItemHeight` | 44 | Two-line workspace row target |
| `workspaceRailItemGap` | 4 | Vertical space between workspace rows |
| `projectMenuWidth` | 420 | Principal project menu command-center width |
| `transcriptMaxWidth` | 680 | Agent Markdown prose measure |
| `documentMaxWidth` | 720 | Markdown file-preview prose measure |
| `markdownOutlineWidth` | 200 | Trailing "On This Page" outline rail |

## Color Tokens

All palette colors are dynamic `sRGB` colors. Foreground text uses native label colors.

| Token | Light | Dark | Role |
|---|---|---|---|
| `chrome` | `#E7E3DD` | `#23262A` | Titanium toolbar, headers, status, tab strip |
| `canvas` | `#DEDAD3` | `#181A1D` | Window and empty-state background |
| `sidebar` | `#EEEBE3` | `#202328` | Explorer, Git, and Gemma sidecar bases |
| `panel` | `#F2F0EC` | `#292C30` | Pearl cards and local panel content |
| `raised` | `#D4D0C9` | `#34383D` | Raised controls and palette body |
| `editor` | `#F8F7F4` | `#191B1E` | Matte porcelain editor, code, and terminal base |
| `tabInactive` | `#E5E1DB` | `#25282C` | Inactive tabs |
| `border` | `#BFBAB2` | `#42474D` | Dividers and control outlines |
| `selection` | `#DED1C6` | `#4B3730` | Selected rows and tabs |
| `chromeSelection` | `#F7F3EE` | `#4D4742` | Bright warm glass selection for chrome tabs |
| `chromeSelectionInk` | `#2B2724` | `#F2EFEA` | Text and icons on selected chrome tabs |
| `hover` | `#D8D4CD` | `#383C41` | Hover state |
| `pressed` | `#CCC7BF` | `#44494F` | Pressed state |
| `accent` | `#A44F32` | `#D79570` | Primary emphasis and focus |
| `accentInk` | `#FFF9F2` | `#21150F` | Text on accent fill |
| `workspaceRailTop` | `#1D232B` | `#171C22` | Upper graphite rail gradient stop |
| `workspaceRailBottom` | `#2D3B45` | `#202D35` | Lower petrol rail gradient stop |
| `workspaceRailSolid` | `#252D35` | `#1D252C` | Reduce Transparency rail fallback |
| `workspaceRailForeground` | `#F3F1EC` | `#F3F1EC` | Primary text and icons on the rail |
| `workspaceRailSecondary` | `#B6BEC3` | `#ADB7BD` | Rail metadata and inactive icons |
| `workspaceRailSelection` | `#4C565F` | `#46505A` | Active rail row fill and Reduce Transparency fallback |
| `workspaceRailHover` | `#333C44` | `#2D373F` | Rail hover fill |
| `workspaceRailPressed` | `#46515A` | `#404B54` | Rail pressed fill |
| `workspaceRailBorder` | `#59636B` | `#4C575F` | Rail edge and focused control outline |
| `fileTreeForeground` | `#302E2B` | `#E8E4DE` | Stable Explorer label color, including selection |
| `gitAdded` | `#356B43` | `#7FC58C` | Additions and success |
| `gitModified` | `#8A5B21` | `#D4A45D` | Modified state |
| `gitDeleted` | `#A13E37` | `#E17B70` | Deletions, danger, destructive state |
| `gitUntracked` | `#286E68` | `#63C3B8` | Untracked state and code cyan |

Color rules:

- Reserve accent for focus, primary action, and active indicators.
- Use bright warm `chromeSelection` glass and dark-ink `chromeSelectionInk` for selected sidebar and center tabs.
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
| `panelEdgeShadow` | 14% warm black | Directional depth between side panels and center |

Depth rules:

- Use borders before shadows for structure.
- Use `shadowSoft` only for raised local content.
- Use `shadowFloating` for modal overlays such as the palette.
- Use the `0.12` black scrim behind blocking overlays.
- Allow one signature gradient on the workspace rail and a restrained directional sheen on shared chrome.
- Keep editor, terminal, Explorer, Git, and inspector content matte and gradient-free.
- Do not add broad glow, deep drop shadows, or decorative glass layers. A selected interactive
  surface may use one native glass layer with a top-lit hairline highlight and one soft shadow.

## Typography

| Token | Size | Typical use |
|---|---:|---|
| `micro` | 11 | Shortcuts, metadata, compact badges |
| `caption` | 12 | Secondary labels and controls |
| `label` | 12.5 | Tabs and compact actions |
| `body` | 13.5 | Main UI copy |
| `uiSize` | 14 | Fields and standard interface text |
| `headline` | 16 | Panel headers |
| `title` | 17 | Section titles and strong empty states |
| `display` | 24 | Large empty-state titles |
| `editorSize` | 16 | Source editor |
| `terminalSize` | 20 | Terminal |

Type rules:

- Use the native system face for interface text.
- Use serif only for editorial headers and empty-state titles.
- Use monospaced text for paths, code, shortcuts, counts, and technical metadata.
- Use JetBrains Mono Regular (400) for code. Fall back to the system monospaced font.
- Keep contextual code ligatures enabled in the editor and terminal.
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
| `panelCollapse` | Ease-out 0.20 / no bounce | Native side-panel collapse and reveal |
| `selection` | Spring 0.24 / 0.86 | Selection movement |

Motion rules:

- Disable optional motion when Reduce Motion is enabled.
- Start side-panel feedback on the interaction frame. Collapse width over 0.20 seconds with an
  ease-out curve so the transition never feels queued or delayed.
- While hiding, roll sidebar and inspector content toward their owning outer edge and clip it to
  the shrinking pane. Do not fade, blur, scale, snapshot, or animate the center native surface.
- Use a short shine after refresh, shake for Git error, and small jump for a new terminal.
- Keep tab selection responsive through fill or indicator changes inside fixed bounds.
- Never animate or transform the outer geometry of sidebar tabs.
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
- Use the pinned Material Icon Theme v5.37.0 SVG set for file and folder identity in
  Explorer and Git change trees.
- Resolve file icons through one shared manifest-backed resolver. Match an exact file name first,
  then the longest compound extension, then shorter extensions, then the default file icon.
- Resolve folder icons by exact folder name and expansion state, with the default closed or open
  folder icon as fallback.
- Keep Material icon colors intact. Do not tint file or folder identity icons with accent or Git
  status colors.
- Prewarm and cache Material images before row configuration or SwiftUI body evaluation. Never
  decode SVG data in draw, layout, cell configuration, or per-row view paths.
- Keep Git state in the existing trailing semantic status slot. Material file icons never replace
  the `M`, `A`, `D`, `R`, `C`, `U`, conflict, or fallback status labels.
- Use one stable symbol for each typed action.
- Pair text with icons when the action is not obvious.
- Do not add decorative duplicate icons.
- Keep compact icon buttons at least 30 points.
- Give icon-only controls a help string and accessibility label.

### Interaction States

Every interactive control must define these states where relevant:

- Normal: clear fill and normal opacity.
- Hovered: semantic hover fill.
- Pressed: stronger pressed fill. Scale only isolated compact controls when motion is allowed.
- Selected: one native tinted glass surface with stable geometry. Do not add an accent border,
  underline, or leading rule.
- Focused: accent-tinted fill and 1.5-point focus ring.
- Disabled: visible control with `0.45` opacity.

Interaction geometry rules:

- Tabs, full-width rows, segmented cells, and header controls keep identical outer bounds in every state.
- Hover, press, selection, focus, badges, and count changes never alter frame, padding, alignment, or baseline.
- Use scale feedback only for isolated controls with visible space around every edge.

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
- Center the project command trigger against the full app window, independent of split widths.
- Keep the project identity readable and middle-truncated inside the full-width hit target.
- Keep the project command trigger text-only. Do not show a folder or disclosure icon.
- Preserve every existing project command in a 420-point top-anchored dropdown that matches the trigger width.
- Align the dropdown edges exactly with the project command trigger.
- Clicking any part of the project menu opens the existing project commands menu.
- Show the pointing-hand cursor across the full 420-point trigger.
- Keep the dropdown flush with the workspace content edge. Use a straight top edge with no callout arrow.
- Keep the dropdown mounted while animating its clipped reveal geometry.
- Reveal it downward from its fixed top edge. Dismiss it by sliding and clipping upward into that edge.
- Keep project-menu motion reversible and bounce-free. Do not use whole-surface scale, blur, or fade-only transitions.
- Show and dismiss the dropdown without decorative reveal when Reduce Motion is enabled.
- Keep project command rows keyboard-focusable without drawing the native accent focus ring.
- Draw one project-command glass surface. Hide the toolbar item's shared background.
- Use a quiet native label inside the system toolbar material. Do not add a tinted icon tile, nested pill, glow, or heavy shadow.
- Double-clicking visually empty titlebar or toolbar background toggles native window zoom reliably.
- Toolbar controls keep their own click behavior and never trigger window zoom.
- Put Gemma, focus mode, and inspector in primary actions.
- Synchronize the focus control with effective side-panel visibility. Its master transition must
  animate every split item whose visibility changes with the same duration.
- Keep branch, focus state, estimated LLM tokens for the selected text file, and zoom in the
  26-point status bar. Place the token estimate immediately before zoom and prefix it with `~`
  because exact tokenization depends on the selected model.
- Use thin dividers between sidebar, center, inspector, and status bar.
- Give the sidebar a very light shadow that extends rightward into the center from its trailing
  edge. Mirror it leftward from the inspector's leading edge. Use `panelEdgeShadow`; fade each
  effect across 6 points inside the center pane so split boundaries cannot clip it.

### Workspace Rail

- Keep the rail outside `WorkspaceView`, its toolbar, split view, and status bar.
- Use a fixed 176-point rail with one hairline divider on its trailing edge.
- Keep the Workspaces header. Do not add a Threads tab or separate panel body.
- Treat each workspace as one collapsible group with its 44-point workspace header and nested thread rows.
- Keep the labeled Add Workspace action below the scrollable workspace groups.
- Show only the full project name as primary identity. Never use initials, monograms, folder icons,
  or visible paths in workspace rows.
- Show `Command-1` through `Command-9` below the matching project name in smaller monospaced
  secondary text. Ordered catalog position defines the shortcut number.
- Keep workspaces after position 9 available in the rail without assigning a number shortcut.
- Reserve `Command-0` for opening a new workspace.
- Place 44-point workspace rows in one vertical column with 4-point gaps and 8-point horizontal insets.
- Put one labeled `Add Workspace` action below the scrollable workspace list.
- Support drag-and-drop reordering within the rail and persist the new order.
- Give every workspace row a native context menu for activation, Finder, path copy, ordering, and close.
- A context-menu close targets that item. It must not switch or close the active workspace first.
- Mark the active workspace with label weight, a brighter neutral shortcut, and exactly one glass
  selection indicator behind the project rows. Move and resize that indicator between measured row
  frames with the center-tab spring. Keep all row content stationary and clip it to the rail list.
  Do not add a checkmark, leading accent bar, duplicate glass, or floating-card treatment.
- Show loading, unavailable, and error accessories without replacing project identity.
- Keep the full path in help and accessibility text without rendering it in the row.
- Use rail-specific hover, pressed, focused, selected, and disabled fills so contrast stays stable.
- Keep optional motion limited to quick opacity and scale feedback. Disable it under Reduce Motion.
- Keep the rail dark in light and dark appearance. Use the graphite-to-petrol gradient as its only signature depth effect.
- Use `workspaceRailSolid` when Reduce Transparency is enabled.
- Use a faint top-edge sheen and one trailing hairline. Do not add glow, heavy shadows, pills, or dock magnification.

#### Threads

- List terminals that run or ran an agent below their workspace header across every live workspace.
- Keep workspace groups in workspace rail order. Do not add a Threads tab.
- Make each workspace group collapsible. Show a trailing disclosure chevron on the workspace header only when the group has at least one thread.
- Reserve the trailing chevron gutter so the running badge and status accessory keep their position when the chevron appears.
- Expand the active workspace by default. Keep other groups collapsed until the user expands them. Auto-expand a workspace when it becomes active.
- Do not render a "No threads yet" row. A workspace with no agent threads shows only its header, with no chevron and no thread rows.
- Render an expanded workspace group as one recessed container that holds the header and its thread rows. Use a quiet sunken fill with rounded corners and a top-lit hairline. The recessed group is a sunken surface, not a floating card; it adds no border and no drop shadow.
- Keep threadless workspaces and collapsed groups as plain rows with no container.
- Separate workspace groups with vertical spacing so each project reads as one block.
- Show a quiet running-count badge on the workspace header only while the group is collapsed. When the group is expanded, the running rows already show their state, so the header omits the badge. Do not shift the project name when the badge appears or its count changes.
- Each thread row shows a status dot, the agent name, and a trailing relative time for done rows. Use a filled accent dot for running and a hollow muted dot for done. A soft running pulse is allowed and must stop under Reduce Motion.
- Keep each nested row at `rowHeight` 28 with an inset shared selection pill and pointer cursor. Align the thread content under the workspace name.
- Keep row geometry stable across running, done, hovered, pressed, and selected states.
- Detect agents from each terminal pty foreground process. Match its argv against the shared agent name list.
- Do not depend on OSC 133. Atelier does not inject shell integration.
- Keep a thread while its terminal stays open. Move it from running to done when the agent exits.
- Remove the thread when its terminal closes. Do not create a separate thread history store.
- Refresh only while the Workspace panel is mounted and the app is active.
- Keep the disclosure chevron, workspace-header, and nested-thread hit targets separate.
- Animate expand and collapse with a short spring. Disable the motion under Reduce Motion.
- Clicking a thread activates its workspace when needed, selects the matching terminal tab, and focuses its terminal.

Workspace item states:

| State | Visual treatment | Interaction | Accessibility value |
|---|---|---|---|
| Active | Semibold name, brighter neutral shortcut, flat selection band | Selecting again keeps current session | `Selected, available` |
| Inactive | Primary name, secondary shortcut, clear fill | Selects existing live session | `Available` |
| Loading | Secondary name and shortcut, native progress indicator | Disabled until restore finishes | `Loading` |
| Unavailable | Primary name, secondary shortcut, `questionmark.folder` accessory | Selects item and presents recovery context | `Unavailable` |
| Error | Primary name, secondary shortcut, semantic error accessory | Selects item and presents error context | `Error` |
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
- Make every sidebar tab cell occupy the full 40-point `panelHeaderHeight` envelope.
- Make the Explorer and Git tab strip span the full sidebar width edge-to-edge.
- Use zero outer horizontal padding and zero spacing between sidebar tab cells.
- Separate tab cells with the pill insets themselves. Do not draw hairline dividers between tabs.
- Put a compact contextual toolbar at the top of the selected tab body, directly below the tab bar.
- Right-align New File and New Folder in the Explorer toolbar. Right-align Refresh in the Git toolbar.
- Render only the selected body's actions. Keep the tab label, count, selection target, help, and accessibility text intact.
- Keep every sidebar tab hit target aligned to all four edges of the header envelope.
- Render the selected sidebar tab as an inset `rowRadius` rounded pill of translucent `chromeSelection` glass with a
  top-lit hairline highlight. Keep the full header envelope as the hit target. Use
  `chromeSelectionInk` for its label and icon.
- Render exactly one glass indicator behind the Explorer and Git labels. Move and resize it between
  measured tab frames with the center-tab spring. Keep tab content stationary, clip the indicator to
  the header, and never cross-fade or duplicate it.
- Use one native label line box so each tab icon and title share a baseline.
- Show the Git change count as a trailing semantic badge that never shifts the centered label.
- Keep sidebar tab geometry stable across normal, hovered, pressed, selected, and count-change states.
- Keep body toolbar actions at 24 points, with quiet hover and pressed fills.
- Keep selected file labels in the primary text color. Use one rounded, warm-tinted native material
  surface with no accent edge and no inverted text.
- Treat each complete file-tree row, including its icon, label, and trailing empty area, as one
  pointer-cursor hit target.
- Every Explorer item keeps the pointing-hand cursor over its disclosure, icon, label, badges, and
  trailing row area. No item subview may expose the text or arrow cursor.
- Vertically center the disclosure, icon, and label within every file-tree row.
- Use overlay Explorer scroll indicators that fade away when scrolling stops.
- Keep the base file or folder icon and add an `arrow.turn.up.right` badge after symlink names.
- Do not expand directory symlinks from Explorer.
- Keep Git-ignored files and folders visible, but render their row content at reduced opacity.
- Expose the ignored state through row help text so it is not conveyed by color alone.
- Dispatch Explorer primary clicks on mouse-down so file previews and folder toggles start immediately.
- Explorer single-click opens one replaceable preview.
- Explorer double-click opens or promotes a permanent tab.
- Command-clicking a file or folder inserts its workspace-relative path into the selected terminal.
  Prefix the path with `@` and append one space. If a terminal is not selected, preserve the
  normal single-click behavior.
- Right-clicking a file or folder exposes Rename, Move to Trash, Copy Path, and Add to `.gitignore`.
- Rename requires a new-name prompt. Move to Trash requires destructive confirmation.
- Disable Add to `.gitignore` when the item is already ignored or is the `.gitignore` file itself.
- Quick Open and every non-Explorer route open permanent tabs.

### Center Tabs

- Use titanium chrome for the strip and porcelain for the selected editor surface.
- Keep Back and Forward available through menus and shortcuts, not inside the tab strip.
- Keep the final remaining terminal tab open and non-closable.
- Confirm before closing any other terminal while Claude Code or Codex is the detected foreground agent.
- Close other terminals without confirmation when only the shell or a regular command is running.
- Keep tab widths between 112 and 220 points, with 152 ideal.
- Render the selected center tab as an inset `rowRadius` rounded pill of translucent `chromeSelection` glass with a
  top-lit hairline highlight. Keep the full strip-cell envelope as the hit target. Use
  `chromeSelectionInk` for its label and icon. Do not add an accent top rule or selection border.
- Render exactly one glass selection indicator behind the center-tab content. Move and resize it
  between measured tab frames with a `0.28` response, `0.82` damping spring. Keep labels, icons,
  close controls, tab geometry, and editor content stationary. Clip the indicator to the tab strip,
  never cross-fade or duplicate it, and switch it instantly under Reduce Motion.
- Mark preview with regular label weight and `0.72` opacity. Do not add another icon.
- Place the close control at the left edge of every closable tab.
- Show close only on the selected or hovered tab.
- Preserve drag reorder, rename, context menu, and word-wrap behavior.
- Keep Response and editor actions in one trailing group after the scroller.
- Keep the Response action visible for every selected center-tab kind.
- Keep New Terminal as the final far-right action. Its position never changes with tab selection.
- Give the trailing action group `spaceXS` horizontal insets and `spaceXS` spacing between controls.
- Reopen Closed Tab restores permanent file tabs only.
- Restore the previous session per workspace on relaunch: reopen file tabs (path, order,
  preview or permanent disposition, word wrap) and terminal tabs (count and titles) at the
  workspace root, and reselect the active tab. Skip missing files, Git diff tabs, and Gemma
  tabs. Terminal processes and scrollback are not restored; restored terminals start fresh
  shells. Fall back to a single terminal when nothing is restorable.

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

- Keep repository, branch, commit input, and change groups in the sidebar.
- Present repository identity as one compact card with the workspace name, shortened path,
  current branch, and branch-switch menu.
- Show Staged and Changes as separate, always-visible sections. Count untracked files under
  Changes. Do not add a summary selector above the composer.
- Render each change section as an expandable directory tree. Collapse single-child directory
  chains into one workspace-relative path while keeping changed files as actionable leaf rows.
- Keep each change row at `rowHeight` 28. Show Git status in the trailing slot at rest, then
  overlay row actions in that slot on hover or keyboard focus without reserving extra width.
- Highlight the leaf matching the selected center diff tab. When a folder is collapsed, show its
  descendant file count. Option-clicking a folder toggles its whole visible descendant branch.
- Keep directory guide lines low contrast so file names and Git status remain the primary signals.
- Use an overlay Git scroll indicator that fades away when scrolling stops. Never keep it
  persistently visible.
- Keep the commit composer multiline and focused on direct text entry. Do not show a separate
  Gemma trigger, utility footer, or keyboard-hint row inside the composer card.
- Render Push as one primary control without a trailing options segment. It runs the current
  generated publish pipeline for the active branch.
- Keep change-section headers text-only. Do not add filter or overflow controls beside them.
- Show recent commits below changes with subject, author, relative time, short hash, and a HEAD
  marker on the newest commit. Anchor each short hash at the row's top-trailing corner. Keep the
  default list bounded and expand it only on request. Resolve each author avatar from the commit
  email through GitHub or Gravatar, with a neutral system fallback when no image exists.
- Refresh Git state after external commits, pushes, checkouts, and branch switches by
  watching only repository metadata that can change the visible snapshot: `.git/index`,
  `.git/HEAD`, `.git/packed-refs`, and `.git/refs/**`.
- Keep unrelated `.git` internals, build products, and dependency directories ignored.
  Coalesce watcher bursts through the existing debounce before refreshing.
- Run Atelier-owned Git subprocesses with optional locks disabled so background reads
  never rewrite watched metadata and trigger another refresh.
- Generate one editable Conventional Commit subject from changed file paths only. Never send diff or file contents.
- Replace the commit action with Push. Push must generate a fresh Gemma subject, commit the
  selected changes, then push the current branch.
- Show progress across generation, staging, commit, and push. Disable duplicate generation and
  push while the pipeline runs.
- Stop commit-message generation after 30 seconds. Restore the idle Push state and show a
  retryable error without staging, committing, or pushing.
- Open file diffs as center tabs, not inside the Git sidebar.
- Use semantic green, orange, red, and teal only for Git meaning.
- Keep diff line numbers in a fixed 48-point gutter.
- Use monospaced selectable diff text.
- Confirm destructive discard actions with a native alert.

### Editor and Terminal

- Keep the center work surface the brightest large region. It must remain matte, quiet, and highly legible.
- Keep code gutters and terminal backgrounds aligned with the editor token.
- Use the editor surface color for source, diff, and terminal content.
- Inset the native terminal view by `spaceM` horizontally and `spaceS` vertically. Fill the
  inset area with the editor surface color.
- Hide the terminal scroll indicator. Keep mouse and trackpad scrolling available.
- Use native AppKit text and terminal views through narrow representable bridges.
- Use the native AppKit find bar for editable and read-only text files.
- Open file search with `Cmd-F`. Search incrementally and highlight visible matches without dimming
  the editor content.
- Keep native previous, next, replace, replace-all, selection, match-mode, and result-count behavior.
- Keep search inside the file scroll view. Closing search restores focus to the editor.
- Keep editor word wrap as a per-file setting.
- Offer Source and Preview modes for `.md` and `.html` text files. Open both Markdown and HTML in
  Preview mode by default. Keep the native editor mounted while Preview is visible, and keep
  explicit per-tab mode changes session-only.
- Keep each rendered preview mounted while its tab remains open. Preserve preview scroll, selection,
  outline, and page state across tab switches and Source/Preview switches.
- Render Markdown through the native Atelier Markdown surface. Render HTML from its original file
  URL in a non-persistent WebKit surface. Allow relative resources from the containing directory
  and run the page's scripts so interactive local previews render correctly.
- Render Markdown Preview as one read-only, selectable `NSTextView` backed by one `NSTextStorage`.
  Keep every rendered block in that single native document so selection can cross headings,
  paragraphs, lists, quotes, code, tables, and Mermaid fallback content. Preserve native `Cmd-C`.
- Render Markdown file-preview body text at `editorSize` so Source and Preview share the same
  base text size. Center a `documentMaxWidth` text container, use roomier line and section spacing,
  and render H1/H2 with the editorial serif face.
- Treat Markdown as an editorial document. Keep prose on a readable measure and give heading
  levels distinct scale, weight, spacing, and restrained accent rules.
- When a Markdown file has two or more headings, show a quiet trailing "On This Page" outline in
  both Source and Preview modes. Hide the outline when the center column is too narrow to keep a
  readable measure. Keep outline state session-only.
- Outline clicks reveal the source heading line in Source mode and the rendered heading character
  range in Preview mode. Keep Preview outline selection in sync with the native document scroll
  position. Outline rows use the pointer cursor on hover. Outline scroll chrome uses overlay
  auto-hiding scrollers like other panels; never leave a permanent scroller gutter.
- While Markdown/HTML Preview is visible, keep the native editor mounted but hide it from AppKit
  hit-testing and cursor-rect participation (`isHidden`, non-selectable) so NSTextView I-beam does
  not bleed through the preview or On This Page rail.
- Parse each Markdown source once per content change and share its blocks and outline with Source
  and Preview. Build one attributed native document from those blocks. Never build or measure a
  second rendered document tree to decide outline visibility.
- Keep Markdown scroll hot paths cheap: cache the attributed document until source, scale, or
  appearance changes; map headings to TextKit character ranges; update outline selection only when
  the active section ID changes; and never animate the outline rail during passive document scroll.
- Outline jumps use source line locations or native TextKit character ranges. They must not rebuild
  the document or replace the mounted text view.
- Render unordered, ordered, and task lists, block quotes, code blocks, tables, and dividers as
  distinct attributed regions inside the single native document. Keep the palette quiet and
  reserve terracotta for semantic accents.
- Render fenced code with cached syntax-token colors when a language is known. Preserve source
  whitespace, wrap long lines to the available preview width, and fall back to readable
  monospaced text when highlighting is unavailable. Do not horizontally scroll code blocks.
- Render inline code as a compact monospaced accent block within prose. Keep surrounding text
  wrapping naturally.
- In Markdown file Preview mode, render valid CSS hex color tokens (`#RGB`, `#RGBA`, `#RRGGBB`,
  and `#RRGGBBAA`) with an `editorSize` inline square filled by that sRGB color. Apply the swatch in
  prose, inline code, tables, and fenced code without changing Source mode or code-block copy content.
- Pure inline-code table cells (`path` only) use one continuous monospaced accent chip so
  soft-wrapped paths fill as a single shape. Do not paint per-line fragment backgrounds that
  zebra-stripe multi-line skill paths in Markdown preview tables.
- Keep wrapped table rows self-sizing inside the native text container. Wide tables wrap their
  cells without overlapping content or splitting selection into another scroll surface.
- Put the Source/Preview toggle in the trailing editor action group. Keep find and word-wrap
  commands scoped to Source mode.
- Use `Cmd-E` to toggle Source and Preview for the active `.md` or `.html` file. Keep its existing
  Use Selection for Find behavior for other text files.
- With a non-empty editor selection, `Cmd-Shift-C` inserts
  `@<workspace-relative-path>:<first-line>~<last-line> ` into the most recently selected terminal
  and switches to that terminal. Keep exactly one trailing space. Disable the command when no
  text is selected.
- Promote a preview before the first edit is saved.
- Preserve first responder across palette, zoom, inspector, and sidecar transitions.
- Keep the terminal's structural parent and proposed size stable while a sidecar opens or closes. Never reserve terminal width for agent responses.
- Preserve terminal keyboard protocols. In legacy mode, `Shift-Enter` must send a newline distinct
  from `Enter`, and unmodified arrow keys must reach interactive TUI prompts. When enhanced keyboard
  reporting is active, defer to its negotiated encoding.

### Gemma Sidecar Assistant

The inspector pane hosts a context-aware Gemma assistant instead of a static
metadata panel. It reads the active center tab and helps with the current work.
It is read-only: it never writes files, runs shell commands, or performs Git
actions. Every run is cancellable and pauses when Ollama is unreachable.

- Use `sidebar` as the inspector pane base so the left and right side panels share one background.

The sidecar uses a one-feed, one-input layout with three fixed zones:

- Header: accent icon tile, title, `kind - status` caption line, an intent chip, and a
  gear button. The gear opens a popover with the feature toggles (auto-diagnose,
  session journal). No toggle lives in the panel body.
- Feed: one scroll view that holds every output as a card sharing one visual
  language: journal milestone rows, Guardian diagnosis card, Pre-commit Whisper
  advisory card, Intent Guard drift card, user and assistant turns, tool activity
  rows, and the Claude handoff card. A background feature renders nothing while it
  has nothing to say; it never reserves fixed space.
- Input: one horizontal chip row of context quick actions directly above one prompt
  field with send, stop, and clear controls. There is exactly one text input in the
  panel body; the intent is edited through the header chip's popover.
- Show the standard empty state when no center tab is selected.
- Keep the response area streaming and non-blocking. Show connection-error text when
  a run fails; never block the UI.
- Use the sidecar's own Gemma runtime, separate from the Gemma chat tab. The clear
  control resets only the sidecar session, never the chat tab.
- Inject the active tab context (kind, file path, working directory, git diff target,
  editor selection) into each user prompt. Do not change the runtime system prompt.

Quick actions per tab kind, sent as one-shot prompts into the response area:

| Tab kind | Quick actions |
|---|---|
| File | Explain file, Summarize file, Find usages |
| Git diff | Review diff, Suggest commit message |
| Terminal | Explain last error, Explain command |
| Editor selection | Explain selection |

- Disable an action when its context is absent (for example, no editor selection).
- Terminal quick actions read the selected terminal scrollback through the read-only
  `read_terminal_output` tool. Bound the snapshot to at most 400 lines.

Registry and feature slots:

- Keep all sidecar code under `app/Atelier/Sources/Atelier/Agent/Sidecar`.
- Build the container as a plugin-style registry. The container and its model must not
  change when a feature is implemented. Each feature owns one file, its own state,
  cadence, and toggle, and is constructed with a shared read-only service surface.
- Run background features one bounded call at a time on a dedicated serialized
  background runtime. Every feature is read-only and cancellable, and skips work when
  Ollama is unreachable.

The five background features, all read-only and cancellable:

| Feature | Purpose |
|---|---|
| Terminal Guardian | Offer a read-only explanation after a failed terminal command |
| Claude Code Briefing | Summarize recent agent activity as quick actions |
| Session Journal | Keep a periodic read-only summary of the session |
| Intent Guard | Track the stated intent for the current work |
| Pre-commit Whisper | Surface read-only findings before a commit |

### Agent Responses

- Use a readable transcript width capped at 680 points.
- Keep user and assistant hierarchy clear without chat-bubble decoration everywhere.
- Use cards for tool activity and structured results.
- Present agent responses above the complete center work surface at every window width. The
  overlay never becomes a split peer or consumes terminal, editor, diff, or Gemma layout space.
- Open the response overlay at the full center-content width below the tab strip.
- Provide one header control that toggles between full width and a trailing half-width mode.
- Opening the overlay from the Response action always restores full-width mode.
- Restore at most 100 newest final responses for the current workspace at startup.
- Treat restored responses as read, then count only newly monitored responses as unread.
- Start transcript restore only when a workspace first becomes active. Keep live monitoring
  running after activation, including while another workspace is selected.
- Bound startup discovery to the 100 newest transcript files per source root and 16 MiB of
  uncached transcript data per refresh.
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
| `Cmd-Shift-,` | New Terminal and run `c` for Claude Code |
| `Cmd-Shift-.` | New Terminal and run `cc` for Codex |
| `Cmd-Shift-;` | New empty terminal |
| `Cmd-P` | Quick Open |
| `Cmd-Shift-P` | Command Palette |
| `Cmd-F` | Find in active text file |
| `Cmd-Option-F` | Find and replace in active text file |
| `Cmd-G` | Next file-search match |
| `Cmd-Shift-G` | Previous file-search match |
| `Cmd-E` | Toggle Source and Preview for the active Markdown or HTML file |
| `Cmd-Shift-C` | Insert selected editor line reference into terminal |
| `Cmd-W` | Close active closable center tab |
| `Ctrl--` | Back |
| `Ctrl-Shift--` | Forward |
| `Cmd-Shift-E` | Toggle Left Panel |
| `Cmd-Shift-R` | Toggle Right Panel |
| `Cmd-+` | Zoom In |
| `Cmd--` | Zoom Out |
| `Cmd-0` | Actual Size |
| `Cmd-Shift-F` | Toggle Focus Mode |
| ``Cmd-` `` | Next Workspace (cycles, wraps to first) |
| `Option-Z` | Toggle Word Wrap |

Rules:

- Menu items, palette actions, and toolbar controls must call the same typed action.
- Agent terminal shortcuts create a fresh terminal in the active workspace, type the exact alias,
  and submit it once.
- `Cmd-W` never closes the workspace window. With no active tab or only the final terminal active, it does nothing.
- `Cmd-W` asks for confirmation only when Claude Code or Codex is the detected foreground agent.
- Keep Reopen Closed Tab available through menus and the command palette without a default shortcut.
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

## Runtime Diagnostics Contract

Atelier exposes a terminal-first Runtime Probe for causal runtime evidence. Diagnostics must remain bounded, private, and independent from SwiftUI rendering.

- Write schema-versioned snapshots atomically to the bundle cache at `Runtime/current/snapshot.json` no more than once per second.
- Keep process sampling, heartbeat evaluation, snapshot encoding, mailbox polling, and file writes off the main thread.
- Read workspace, tab, editor, and AppKit geometry only on `MainActor`. Transfer immutable `Sendable` snapshots to the diagnostics worker.
- Run blocking Git subprocess waits on a bounded dedicated executor, never on Swift's cooperative executor. Report active count, queued count, concurrency limit, and oldest active age.
- Report the selected file-tree root load state, direct entry count, load age, and a sanitized error code. Never expose absolute paths or raw error text.
- Keep terminal controller metrics bounded. Report diagnostic ownership, active and attached state, process state, selected controller, and first-responder identity without terminal output.
- A terminal may become first responder only when its tab is selected in the active workspace. Hidden workspaces must keep native terminals mounted but inactive and release terminal focus.
- Allow one outstanding main-thread heartbeat. Never queue heartbeat work while an earlier ping remains pending.
- Reuse `ProcessMetrics` and the watchdog sample cadence. Never run two process samplers concurrently.
- Keep the flight recorder at 512 events. Aggregate scroll counters into one-second windows instead of recording each frame.
- Record only scalar metrics, diagnostic identifiers, and workspace-relative paths. Never record file content, selections, terminal output, prompts, responses, diffs, environment values, or credentials.
- Keep verdicts heuristic. Every verdict includes severity, confidence, summary, and raw evidence.
- Keep active probes local to the generated cache mailbox. Use one request at a time, atomic files, current-user permissions, bounded timeouts, and reversible editor scroll restoration.
- Active editor probes must not change focus, selection, content, undo state, or word-wrap state. They must not force full-document layout.
- Diagnostics failures must degrade independently. They must never crash, freeze, force-exit, or alter existing watchdog breach behavior.
- Disable production diagnostics for `--selftest` and when `ATELIER_DISABLE_RUNTIME_DIAGNOSTICS=1`.
- `atelier-doctor capture` is read-only. Each collector reports its own status so one failure never discards other evidence.

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
- For native terminal and editor transitions, capture a visible content sentinel before and after the action. A blank work surface fails even when the tab and process remain active.
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
