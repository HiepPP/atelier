import AppKit

@MainActor
final class FileTreeController: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
    private let service = FileTreeService()
    private var root: FileTreeNode
    private var onSelect: (URL) -> Void
    private var scale: CGFloat = 1
    private var revision = 0
    private weak var outlineView: NSOutlineView?
    private var loadTasks: [URL: Task<Void, Never>] = [:]

    init(rootURL: URL, onSelect: @escaping (URL) -> Void) {
        root = FileTreeNode(url: rootURL, isDirectory: true)
        self.onSelect = onSelect
    }

    func makeView(scale: CGFloat) -> NSScrollView {
        self.scale = scale

        let outlineView = NSOutlineView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("File"))
        column.title = "Files"
        column.minWidth = 160
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.rowSizeStyle = .small
        outlineView.intercellSpacing = .zero
        outlineView.usesAlternatingRowBackgroundColors = false
        outlineView.backgroundColor = AppKitThemeAdapter.sidebar
        outlineView.selectionHighlightStyle = .regular
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.action = #selector(handleSelection(_:))
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
        onSelect: @escaping (URL) -> Void
    ) {
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

        guard self.scale != scale else { return }
        self.scale = scale
        guard let outlineView else { return }
        for row in 0..<outlineView.numberOfRows {
            let cell = outlineView.view(atColumn: 0, row: row, makeIfNecessary: false)
                as? NSTableCellView
            cell?.textField?.font = font
        }
    }

    func stop() {
        cancelLoads()
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

    @objc private func handleSelection(_ sender: NSOutlineView) {
        guard sender.selectedRow >= 0,
              let node = sender.item(atRow: sender.selectedRow) as? FileTreeNode else { return }
        if node.isDirectory {
            sender.isItemExpanded(node) ? sender.collapseItem(node) : sender.expandItem(node)
        } else {
            onSelect(node.url)
        }
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
        .systemFont(ofSize: 13 * scale, weight: .regular)
    }

    private func makeCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier

        let icon = NSImageView(frame: NSRect(x: 3, y: 2, width: 14, height: 14))
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.autoresizingMask = [.maxXMargin]

        let label = NSTextField(labelWithString: "")
        label.frame = NSRect(x: 21, y: 0, width: 240, height: 18)
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
