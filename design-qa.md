# Design QA

## Scope

- Source visual: `/Users/hiep/.codex/generated_images/019f78a7-eb0e-72a2-a04f-8f352239824c/exec-c613db82-41b4-48fa-bd99-d6c5b665b81a.png`
- State: Atelier workspace, Explorer selected, README preview, Inspector visible.
- Compact capture: `tmp/design-qa-2026-07-19-executive-alloy/narrow.png` at 900x552.
- Wide capture: `tmp/design-qa-2026-07-19-executive-alloy/wide.png` at 1298x768.
- Combined comparison: `tmp/design-qa-2026-07-19-executive-alloy/comparison.png`.
- Sidebar issue references: the Explorer and Git header crops supplied on 2026-07-19 at 12:40 and 12:41.
- Explorer body-toolbar capture: `tmp/design-qa-2026-07-19-executive-alloy/sidebar-body-explorer-actions.png`.
- Git body-toolbar capture: `tmp/design-qa-2026-07-19-executive-alloy/sidebar-body-git-actions.png`.
- The latest Git capture was compared with the supplied Git issue crop in one visual comparison input.
- Project command issue reference: the toolbar crop supplied on 2026-07-19 at 13:02.
- Project command capture: `tmp/design-qa-2026-07-19-executive-alloy/project-command-popover-wide.png`.

## Comparison

- The four-zone hierarchy matches the source: dark rail, titanium Explorer, porcelain editor, pearl Inspector.
- Terracotta marks the active workspace, Explorer tab, file selection, editor tab, and syntax accents.
- Chrome uses a restrained sheen while Explorer, editor, terminal, and Inspector remain matte.
- Compact mode preserves the rail, center tabs, project menu, response action, and status bar.
- Native macOS toolbar controls remain system-owned and keep all existing commands.
- The sidebar header now contains only Explorer and Git tabs without embedded or detached action controls.
- A compact right-aligned toolbar sits directly below the tabs, inside the selected body.
- Explorer exposes New File and New Folder in its body toolbar. Git exposes Refresh in its body toolbar.
- The project command trigger is text-only. Its popover matches the full 420-point trigger width.
- The trigger and popover stay centered in compact and wide window layouts.

## Interaction Checks

- Explorer and Git remain available in the shared sidebar.
- Switching tabs replaces the contextual body toolbar and hides inactive actions.
- Git refresh remains clickable and keeps its native loading state and accessibility label.
- The project command bar opens from its center, left edge, and right edge.
- Clicking the trigger again closes the popover. Open and close preserve the declared accessibility value.
- Compact-to-wide and wide-to-compact zoom completed without a new Atelier crash report.
- README opens as a preview and updates the Inspector context.
- Workspace switching, project menu, terminal creation, response, focus, and Inspector controls retain accessibility labels.
- Compact mode hides unsupported side panels without removing center navigation.

## Findings History

| Severity | Finding | Resolution |
|---|---|---|
| P2 | Initial titlebar was visually detached from the titanium chrome. | Enabled transparent native titlebar treatment and a line separator. |
| P2 | Explorer selection used inverted text on a light fill. | Added a stable Explorer foreground and a terracotta selection edge. |
| P2 | Exact 1440x900 capture exceeded the active display. | Captured the native maximum at 1298x768 and kept deterministic layout-policy coverage. |
| P2 | New File, New Folder, and Refresh appeared beside the tabs, then were incorrectly embedded inside the selected tab. | Moved compact 24-point actions into a right-aligned toolbar at the top of the selected tab body. |
| P2 | The project command trigger used redundant folder and disclosure icons, while its native menu width did not match the bar. | Replaced it with a full-width text trigger and a matching 420-point animated popover. |

## Result

Final result: passed

## Git Sidebar Image Match - 2026-07-21

### Scope

- Source visual truth: `/Users/hiep/Library/Application Support/CleanShot/media/media_oFbRuqXSlq/CleanShot 2026-07-21 at 22.23.40@2x.png`.
- Implementation screenshot: `/tmp/atelier-git-sidebar-live-changes.png`.
- Viewport: 1298x768 app window with the saved 240-point Git sidebar width.
- State: Atelier workspace, Git selected, Changes selected, four working-tree changes.
- Full-view comparison: `/tmp/atelier-git-sidebar-live-comparison.png`.
- Focused comparison: `/tmp/atelier-git-sidebar-live-panel.png`; dense labels and controls remain readable.

### Fidelity Surfaces

- Typography: native macOS type preserves the reference hierarchy and readable project identity.
- Spacing: repository, summary, composer, changes, and history keep the reference vertical order and rhythm.
- Colors: semantic green, orange, and blue accents map to the reference states. Current system appearance is light.
- Image quality: the screen uses native SF Symbols and text. The reference contains no supplied raster brand asset.
- Copy: Git labels, branch action, change states, composer hints, and commit metadata match the intended meaning.

### Interaction Checks

- Staged and Changes switch the visible file group and selected state.
- Filter reveals and hides a working change-filter field.
- Stage, unstage, discard, diff, branch, refresh, commit, and push paths remain connected.
- Recent commits show the current HEAD, author, relative time, and short hash.

### Findings History

| Severity | Finding | Resolution | Post-fix evidence |
|---|---|---|---|
| P1 | Wrapping the whole repository card in a menu compressed its readable identity to one initial. | Kept identity static and moved branch selection to a separate disclosure control. | `/tmp/atelier-git-sidebar-live-changes.png` |

### Residual Differences

- The reference uses dark appearance and a wider sidebar. The live session uses light appearance and a saved 240-point width.
- Real workspace data shows four changes instead of the mock's single database change.
- These are session and data differences. No actionable P0, P1, or P2 mismatch remains.

### Result

final result: passed

## Git Sidebar Control Removal - 2026-07-22

### Scope

- Source visual truth: `/Users/hiep/Library/Application Support/CleanShot/media/media_luAUxpASEr/CleanShot 2026-07-22 at 01.26.48@2x.png`.
- Implementation screenshot: unavailable.
- Intended viewport: 1298x768 app window with the Git sidebar visible.
- Intended state: Atelier workspace, Git selected, light appearance.
- Full-view comparison: blocked because the native capture service rejected its sender.
- Focused comparison: blocked for the same reason.

### Implemented Scope

- Removed the Staged and Changes summary selector.
- Removed the Gemma action from the commit composer.
- Removed the composer utility and keyboard-hint footer.
- Removed the trailing Push options segment.
- Removed the change filter and overflow controls.
- Kept both Staged and Changes as always-visible file sections.
- Kept each commit hash at the row's top-trailing corner.

### Deterministic Checks

- Swift build passed.
- All 205 tests passed.
- Packaged self-test passed.
- The signed app bundle launched from `/Applications/Atelier.app`.

### Findings

- [P2] Native visual evidence is unavailable.
  Evidence: Computer Use repeatedly returned `Sky Computer Use native pipe startup failed`.
  Cause: the service log reports `Sender process is not authenticated` and a missing Guardian rendezvous port.
  Fix: restore the Computer Use authentication channel, then capture and compare the Git sidebar.

### Comparison History

- No visual comparison iteration completed. Source inspection and deterministic verification cannot replace a rendered comparison.

### Result

final result: blocked

## Git Author Avatar - 2026-07-22

### Scope

- Source visual truth: `/Users/hiep/Library/Application Support/CleanShot/media/media_GrLixOR98B/CleanShot 2026-07-22 at 01.47.35@2x.png`.
- Implementation screenshot: unavailable.
- Intended viewport: Git sidebar with Recent commits visible.
- Intended state: real repository commits loaded for the current Atelier workspace.
- Full-view comparison: blocked because the native capture service rejected its sender.
- Focused comparison: blocked for the same reason.

### Implemented Scope

- Added commit author email to Git log metadata.
- Resolve GitHub noreply authors through their GitHub avatar URL.
- Resolve other authors through the Gravatar linked to their Git email.
- Show a neutral native fallback only when no remote avatar is available.

### Deterministic Checks

- Swift build passed.
- All 205 tests passed.
- Packaged self-test passed.
- The configured Git email resolves to a valid 192-pixel Gravatar image.
- The built app launched and remained idle at 0.1 percent CPU.

### Findings

- [P2] Native visual evidence is unavailable.
  Evidence: Computer Use returned `Sky Computer Use native pipe startup failed` for both app state and app discovery.
  Impact: avatar crop and final row alignment cannot be compared against the supplied source crop.
  Fix: restore the Computer Use authentication channel, then capture the Recent commits region.

### Comparison History

- No visual comparison iteration completed. Source inspection and deterministic verification cannot replace a rendered comparison.

### Result

final result: blocked

## Git Sidebar Control Weight - 2026-07-22

### Scope

- Source visual truth: `/Users/hiep/Library/Application Support/CleanShot/media/media_luAUxpASEr/CleanShot 2026-07-22 at 01.26.48@2x.png`.
- Implementation screenshot: `/tmp/atelier-git-compact-320-top.png`.
- Viewport: 1298x768 app window with a 320-point Git sidebar.
- State: Atelier workspace, Git selected, Changes selected, light appearance.
- Full and focused comparison: `/tmp/atelier-git-comparison.png`.

### Fidelity Surfaces

- Typography: native macOS type remains readable. Utility labels use quieter optical weight.
- Spacing: summary, composer footer, push menu, and list toolbar now consume less vertical and horizontal space.
- Colors: semantic Git colors remain intact. Utility controls use secondary foregrounds and flat backgrounds.
- Image quality: all controls use native SF Symbols. No raster or custom image asset is required.
- Copy: labels, shortcuts, branch, file state, and commit metadata preserve their existing meaning.

### Interaction Checks

- Summary selection remains accessible and filters the same Git state.
- Gemma, composer utilities, push menu, filter, and list options retain named hit targets.
- The push menu stays joined to the primary action with a narrower trailing segment.
- Each short commit hash is anchored at the row's top-trailing corner.
- The Git scrollbar is absent in the settled capture and does not remain persistently visible.

### Findings History

| Severity | Finding | Resolution | Post-fix evidence |
|---|---|---|---|
| P2 | Red-boxed controls competed with the primary Push action through large chrome and generous padding. | Reduced fixed heights, fills, padding, indicator width, and menu width while preserving 30-point icon hit targets. | `/tmp/atelier-git-comparison.png` |
| P2 | Commit hashes sat near the metadata baseline instead of the requested top-right position. | Top-aligned each commit row and added a one-point top inset to the trailing hash. | `/tmp/atelier-git-comparison.png` |

### Residual Differences

- Source and implementation contain different live file counts and commit ages.
- The source has Staged selected. The implementation has Changes selected.
- These are live state differences. No actionable P0, P1, or P2 finding remains.

### Result

final result: passed

## Latest QA Status - 2026-07-22

- Applies to `Git Sidebar Control Removal - 2026-07-22` and `Git Author Avatar - 2026-07-22` above.
- Supersedes the earlier control-weight pass because the interface changed afterward.
- Native comparison remains blocked by the Computer Use authentication failure.

final result: blocked
