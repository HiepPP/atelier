# TASK-002 Add the theme adapter

Group: A (dependency foundation)

## Brief

Goal: Add the approved Luminare source and isolate its API behind Atelier-owned helpers.

Change: feature views own button styles -> one theme adapter owns Luminare details

How:

- Add the TASK-001 package source to the Atelier executable target.
- Keep SwiftUI-Introspect pinned at `26.0.1`.
- Add one adapter file with icon, primary, section, and popover content styling helpers.
- Map Luminare tint, height, radius, and padding to `AtelierTheme` values.
- Disable Luminare materials and background effects.
- Keep the adapter unused until the next task.

Files:

- [app/Atelier/Package.swift](../../app/Atelier/Package.swift) (approved package dependency)
- [app/Atelier/Package.resolved](../../app/Atelier/Package.resolved) (resolved source and versions)
- [app/Atelier/Sources/Atelier/AtelierLuminareStyle.swift](../../app/Atelier/Sources/Atelier/AtelierLuminareStyle.swift) (single library boundary)
- [app/Atelier/Sources/Atelier/AtelierTheme.swift](../../app/Atelier/Sources/Atelier/AtelierTheme.swift) (shared token access only when needed)

Expected result:

- Feature views do not import Luminare.
- The adapter preserves current palette values and control dimensions.
- The app builds with no shell or behavior change.

## Verify

- `swift package --package-path app/Atelier resolve` -> all packages resolve.
- `swift build --package-path app/Atelier` -> build completes.
- `rg -l '^import Luminare' app/Atelier/Sources/Atelier` -> only the adapter file is returned.
- `rg -n 'LuminareWindow|LuminarePane|luminareBackground' app/Atelier/Sources/Atelier` -> no matches.
