# TASK-007 Apply SwiftUIX to text viewers

Group: F (read-only text surface)

## Brief

Goal: Use SwiftUIX for the existing read-only file and diff text surface.

Change: custom AppKit text wrapper -> app-owned SwiftUIX text viewer

How:

- Keep [app/Atelier/Sources/Atelier/FileViewer.swift](../../app/Atelier/Sources/Atelier/FileViewer.swift) as the only SwiftUIX boundary.
- Use SwiftUIX `TextView` in constant, read-only, selectable mode.
- Preserve monospaced text, exact palette colors, and current content insets.
- Preserve vertical and horizontal scrolling for long files and diffs.
- Preserve reset-to-top behavior when selected content changes.
- Keep binary and oversized-file messages unchanged.

Files:

- [app/Atelier/Sources/Atelier/FileViewer.swift](../../app/Atelier/Sources/Atelier/FileViewer.swift) (SwiftUIX viewer boundary)
- [app/Atelier/Sources/Atelier/DiffView.swift](../../app/Atelier/Sources/Atelier/DiffView.swift) (inspect only; preserve reuse)

Expected result:

- File and diff text use one SwiftUIX-backed viewer.
- Copy, selection, scrolling, and content replacement match current behavior.
- No other production file imports SwiftUIX.

## Verify

- `swift build --package-path app/Atelier` -> build completes.
- `app/Atelier/.build/debug/Atelier --selftest` -> `SELFTEST: ALL PASS`.
- `rg -l '^import SwiftUIX' app/Atelier/Sources/Atelier` -> only `FileViewer.swift` is returned.
- Native app with a long file and wide diff -> both scroll axes, selection, copy, palette, and reset-to-top pass.
