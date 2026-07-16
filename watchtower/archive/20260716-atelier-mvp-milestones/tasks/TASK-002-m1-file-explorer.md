# TASK-002 M1 file explorer and read-only viewer

Group: M1 (explorer milestone, ships on its own)

## Brief

Goal: Add a lazy file tree and a read-only file viewer to the workspace view.

Change: workspace shows only a placeholder -> workspace shows a file tree and file contents.

How:

- Add FileNode model with lazy children (nil until expanded).
- Wrap NSOutlineView in NSViewRepresentable for lazy expand and smooth scroll.
- Load a directory only when its node expands. Skip .git, node_modules, .build, DerivedData.
- Add a read-only NSTextView viewer using TextKit 2, monospaced, no wrapping.
- Add FileLoader that limits file size and detects binary by null bytes.
- Lay out an HSplitView: tree on the left, viewer on the right. Full steps in [M1.md](M1.md).

Files:

- [app/Atelier/Sources/Atelier/FileNode.swift](app/Atelier/Sources/Atelier/FileNode.swift) (model)
- [app/Atelier/Sources/Atelier/FileTreeView.swift](app/Atelier/Sources/Atelier/FileTreeView.swift) (NSOutlineView wrapper)
- [app/Atelier/Sources/Atelier/FileTreeCoordinator.swift](app/Atelier/Sources/Atelier/FileTreeCoordinator.swift) (data source and delegate)
- [app/Atelier/Sources/Atelier/FileViewer.swift](app/Atelier/Sources/Atelier/FileViewer.swift) (read-only NSTextView)
- [app/Atelier/Sources/Atelier/FileLoader.swift](app/Atelier/Sources/Atelier/FileLoader.swift) (size limit, binary detect)
- [app/Atelier/Sources/Atelier/IgnoreRules.swift](app/Atelier/Sources/Atelier/IgnoreRules.swift) (ignore list)
- [app/Atelier/Sources/Atelier/ContentView.swift](app/Atelier/Sources/Atelier/ContentView.swift) (wire tree and viewer into WorkspaceView)

Expected result:

- The tree shows the workspace root without scanning the whole repo.
- Expanding a folder reads only that folder.
- Clicking a text file shows read-only monospaced content.
- Large files and binary files show a placeholder, not garbage or a hang.

## Verify

- cd app/Atelier && swift build -> ok (build complete).
- Add a FileLoader selftest case -> text, binary, and tooLarge return the right case.
- Launch app, open a repo, expand folders, open a text file and a binary file.
