import AppKit

@MainActor
final class FileTreeController: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
    private let service = FileTreeService()
    private var root: FileTreeNode
    private var onTargetDirectoryChange: (URL) -> Void
    private var onCreateItem: (FileTreeCreationKind, URL) -> Void
    private var onSelect: (URL) -> Void
    private var scale: CGFloat = 1
    private var displayScale: CGFloat = 2
    private var revision = 0
    private weak var outlineView: NSOutlineView?
    private var loadTasks: [URL: Task<Void, Never>] = [:]
    private var contextMenuTarget: URL?

    init(
        rootURL: URL,
        onTargetDirectoryChange: @escaping (URL) -> Void,
        onCreateItem: @escaping (FileTreeCreationKind, URL) -> Void,
        onSelect: @escaping (URL) -> Void
    ) {
        root = FileTreeNode(url: rootURL, isDirectory: true)
        self.onTargetDirectoryChange = onTargetDirectoryChange
        self.onCreateItem = onCreateItem
        self.onSelect = onSelect
    }

    func makeView(scale: CGFloat, displayScale: CGFloat) -> NSScrollView {
        self.scale = scale
        self.displayScale = displayScale

        let outlineView = FileTreeOutlineView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("File"))
        column.title = "Files"
        column.minWidth = 160
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.rowSizeStyle = .custom
        outlineView.rowHeight = rowHeight
        outlineView.intercellSpacing = .zero
        outlineView.usesAlternatingRowBackgroundColors = false
        outlineView.backgroundColor = AppKitThemeAdapter.sidebar
        outlineView.selectionHighlightStyle = .regular
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.action = #selector(handleSelection(_:))
        outlineView.menuProvider = { [weak self, weak outlineView] row in
            guard let self, let outlineView else { return nil }
            return self.contextMenu(for: row, in: outlineView)
        }
        self.outlineView = outlineView

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = AppKitThemeAdapter.sidebar
        scrollView.documentView = outlineView

        outlineView.reloadData()
        outlineView.expandItem(root)
        load(root)
        return scrollView
    }

    func update(
        rootURL: URL,
        revision: Int,
        scale: CGFloat,
        displayScale: CGFloat,
        onTargetDirectoryChange: @escaping (URL) -> Void,
        onCreateItem: @escaping (FileTreeCreationKind, URL) -> Void,
        onSelect: @escaping (URL) -> Void
    ) {
        self.onTargetDirectoryChange = onTargetDirectoryChange
        self.onCreateItem = onCreateItem
        self.onSelect = onSelect
        if root.url != rootURL {
            cancelLoads()
            root = FileTreeNode(url: rootURL, isDirectory: true)
            self.revision = revision
            outlineView?.reloadData()
            outlineView?.expandItem(root)
            load(root)
        } else if self.revision != revision {
            self.revision = revision
            refreshExpandedDirectories()
        }

        guard self.scale != scale || self.displayScale != displayScale else { return }
        self.scale = scale
        self.displayScale = displayScale
        guard let outlineView else { return }
        outlineView.rowHeight = rowHeight
        for row in 0..<outlineView.numberOfRows {
            let cell = outlineView.view(atColumn: 0, row: row, makeIfNecessary: false)
                as? NSTableCellView
            cell?.textField?.font = font
            cell?.textField?.frame.size.height = rowHeight
        }
    }

    func stop() {
        cancelLoads()
        (outlineView as? FileTreeOutlineView)?.menuProvider = nil
        outlineView?.dataSource = nil
        outlineView?.delegate = nil
        outlineView?.target = nil
        outlineView = nil
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        let node = (item as? FileTreeNode) ?? root
        if node.children == nil { load(node) }
        return node.children?.count ?? 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        let node = (item as? FileTreeNode) ?? root
        return node.children?[index] ?? root
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? FileTreeNode)?.isDirectory == true
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        viewFor tableColumn: NSTableColumn?,
        item: Any
    ) -> NSView? {
        guard let node = item as? FileTreeNode else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("FileTreeCell")
        let cell = (outlineView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView)
            ?? makeCell(identifier: identifier)
        cell.textField?.stringValue = node.name
        cell.textField?.font = font
        cell.textField?.textColor = node.isDirectory
            ? AppKitThemeAdapter.accent
            : AppKitThemeAdapter.foreground
        cell.imageView?.image = icon(for: node)
        cell.imageView?.contentTintColor = iconColor(for: node)
        return cell
    }

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        FileTreeRowView()
    }

    func outlineViewItemWillExpand(_ notification: Notification) {
        guard let node = notification.userInfo?["NSObject"] as? FileTreeNode else { return }
        load(node)
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard let outlineView,
              outlineView.selectedRow >= 0,
              let node = outlineView.item(atRow: outlineView.selectedRow) as? FileTreeNode else {
            return
        }
        let target = node.isDirectory
            ? node.url
            : ((outlineView.parent(forItem: node) as? FileTreeNode)?.url ?? root.url)
        onTargetDirectoryChange(target)
    }

    @objc private func handleSelection(_ sender: NSOutlineView) {
        guard sender.selectedRow >= 0,
              let node = sender.item(atRow: sender.selectedRow) as? FileTreeNode else { return }
        if node.isDirectory {
            sender.isItemExpanded(node) ? sender.collapseItem(node) : sender.expandItem(node)
        } else {
            onSelect(node.url)
        }
    }

    @objc private func createFileFromMenu(_ sender: NSMenuItem) {
        guard let contextMenuTarget else { return }
        onCreateItem(.file, contextMenuTarget)
    }

    @objc private func createFolderFromMenu(_ sender: NSMenuItem) {
        guard let contextMenuTarget else { return }
        onCreateItem(.folder, contextMenuTarget)
    }

    private func contextMenu(for row: Int, in outlineView: NSOutlineView) -> NSMenu? {
        let target: URL
        if row < 0 {
            target = root.url
        } else {
            guard let node = outlineView.item(atRow: row) as? FileTreeNode,
                  node.isDirectory else { return nil }
            target = node.url
            outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        contextMenuTarget = target
        onTargetDirectoryChange(target)

        let menu = NSMenu(title: "Explorer")
        let newFile = NSMenuItem(
            title: "New File...",
            action: #selector(createFileFromMenu(_:)),
            keyEquivalent: ""
        )
        newFile.target = self
        menu.addItem(newFile)
        let newFolder = NSMenuItem(
            title: "New Folder...",
            action: #selector(createFolderFromMenu(_:)),
            keyEquivalent: ""
        )
        newFolder.target = self
        menu.addItem(newFolder)
        return menu
    }

    private func load(_ node: FileTreeNode) {
        let isInitialLoad = node.children == nil
        guard node.beginLoading() else { return }
        let url = node.url
        AppLogger.fileTree.debug("Loading directory: \(url.lastPathComponent, privacy: .public)")
        loadTasks[url]?.cancel()
        loadTasks[url] = Task { [weak self, weak node] in
            guard let self, let node else { return }
            do {
                let entries = try await service.children(of: url)
                guard !Task.isCancelled, node.url == url else { return }
                node.apply(entries)
                AppLogger.fileTree.debug(
                    "Loaded \(entries.count) entries from \(url.lastPathComponent, privacy: .public)"
                )
                reload(node, isInitialLoad: isInitialLoad)
            } catch is CancellationError {
                return
            } catch {
                node.failLoading()
                AppLogger.fileTree.error("File tree load failed: \(error.localizedDescription, privacy: .public)")
                reload(node, isInitialLoad: isInitialLoad)
            }
            loadTasks[url] = nil
        }
    }

    private func refreshExpandedDirectories() {
        guard let outlineView else { return }
        var nodes = [root]
        for row in 0..<outlineView.numberOfRows {
            guard let node = outlineView.item(atRow: row) as? FileTreeNode,
                  node.isDirectory,
                  outlineView.isItemExpanded(node) else { continue }
            nodes.append(node)
        }
        for node in nodes { load(node) }
    }

    private func cancelLoads() {
        loadTasks.values.forEach { $0.cancel() }
        loadTasks.removeAll()
    }

    private func reload(_ node: FileTreeNode, isInitialLoad: Bool) {
        if node === root {
            outlineView?.reloadData()
        } else if isInitialLoad, let outlineView {
            var expandedNodes = [node]
            for row in 0..<outlineView.numberOfRows {
                guard let expandedNode = outlineView.item(atRow: row) as? FileTreeNode,
                      outlineView.isItemExpanded(expandedNode) else { continue }
                expandedNodes.append(expandedNode)
            }
            outlineView.reloadData()
            for expandedNode in expandedNodes {
                outlineView.expandItem(expandedNode)
            }
        } else {
            outlineView?.reloadItem(node, reloadChildren: true)
        }
    }

    private var font: NSFont {
        .systemFont(
            ofSize: AtelierFontScaling.snapped(
                AtelierTypography.uiSize * scale,
                displayScale: displayScale
            ),
            weight: .regular
        )
    }

    private var rowHeight: CGFloat {
        ceil(font.ascender - font.descender + font.leading + 4)
    }

    private func makeCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier

        let icon = NSImageView(frame: NSRect(x: 3, y: 2, width: 14, height: 14))
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.autoresizingMask = [.maxXMargin]

        let label = NSTextField(labelWithString: "")
        label.frame = NSRect(x: 21, y: 0, width: 240, height: rowHeight)
        label.controlSize = .regular
        label.font = font
        label.lineBreakMode = .byTruncatingMiddle
        label.autoresizingMask = [.width]

        cell.imageView = icon
        cell.textField = label
        cell.addSubview(icon)
        cell.addSubview(label)
        return cell
    }

    private func icon(for node: FileTreeNode) -> NSImage? {
        let symbol: String
        if node.isDirectory {
            symbol = "folder.fill"
        } else {
            switch node.url.pathExtension.lowercased() {
            case "swift": symbol = "swift"
            case "sh", "zsh", "bash": symbol = "terminal"
            case "json", "plist", "yaml", "yml": symbol = "curlybraces.square"
            case "md", "markdown": symbol = "text.alignleft"
            default: symbol = "doc"
            }
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        image?.isTemplate = true
        return image
    }

    private func iconColor(for node: FileTreeNode) -> NSColor {
        if node.isDirectory { return AppKitThemeAdapter.accent }
        switch node.url.pathExtension.lowercased() {
        case "sh", "zsh", "bash", "swift": return .systemOrange
        default: return AppKitThemeAdapter.accent
        }
    }
}

private final class FileTreeOutlineView: NSOutlineView {
    var menuProvider: ((Int) -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let location = convert(event.locationInWindow, from: nil)
        return menuProvider?(row(at: location))
    }
}

private final class FileTreeRowView: NSTableRowView {
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        AppKitThemeAdapter.selection.setFill()
        NSBezierPath(
            roundedRect: bounds.insetBy(dx: 5, dy: 1),
            xRadius: 7,
            yRadius: 7
        ).fill()
    }
}
