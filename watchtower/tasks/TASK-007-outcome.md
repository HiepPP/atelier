# TASK-007 Outcome

## Outcome

Status: BLOCKED

Changed:
- Replaced the AppKit-only file viewer with a SwiftUIX `TextView` in [FileViewer.swift](../../app/Atelier/Sources/Atelier/FileViewer.swift).
- Kept the viewer inside native two-axis scrolling with app palette colors and existing text insets.
- Added measured content sizing so long lines remain horizontally scrollable without wrapping.
- Cached up to eight measured text sizes by a lightweight content identity.

Contract:
- File and diff content remains read-only and selectable.
- A lightweight content identity resets the scroll view to the top-left when displayed content changes.
- Repeated body updates reuse the cached size instead of measuring up to 2 MB again.
- SwiftUIX stays behind [FileViewer.swift](../../app/Atelier/Sources/Atelier/FileViewer.swift); feature views do not import it.

Verified:
- `swift build --package-path app/Atelier` -> passed.
- `app/Atelier/.build/debug/Atelier --selftest` -> `SELFTEST: ALL PASS`.
- `rg -l '^import SwiftUIX' app/Atelier/Sources/Atelier` -> only [FileViewer.swift](../../app/Atelier/Sources/Atelier/FileViewer.swift).
- Computer Use -> installed app rendered diff content as a non-settable text area.
- Computer Use -> diff scroll area exposed `Scroll Left` and `Scroll Right` plus a vertical scrollbar.
- Installed app remained running after the viewer loaded.

Blocked:
- Full native verification is incomplete.
- Copy, palette, reset-to-top, and long file scrolling still need direct checks.
