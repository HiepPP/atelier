import AppKit

final class FileTreeCoordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
    private(set) var root: FileNode
    private let onSelect: (URL) -> Void
    var scale: CGFloat = 1

    init(rootURL: URL, onSelect: @escaping (URL) -> Void) {
        root = FileNode(url: rootURL, isDirectory: true)
        self.onSelect = onSelect
    }

    func reset(rootURL: URL) {
        guard root.url != rootURL else { return }
        root = FileNode(url: rootURL, isDirectory: true)
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let node = item as? FileNode else { return 1 }
        return loadChildren(node).count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let node = item as? FileNode else { return root }
        return loadChildren(node)[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? FileNode)?.isDirectory == true
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        viewFor tableColumn: NSTableColumn?,
        item: Any
    ) -> NSView? {
        guard let node = item as? FileNode else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("FileTreeCell")
        let cell = (outlineView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView)
            ?? makeCell(identifier: identifier)
        cell.textField?.stringValue = node.name
        cell.textField?.font = .systemFont(ofSize: 13 * scale, weight: .regular)
        cell.textField?.textColor = node.isDirectory
            ? AtelierNativePalette.accent
            : AtelierNativePalette.foreground
        cell.imageView?.image = icon(for: node)
        cell.imageView?.contentTintColor = iconColor(for: node)
        return cell
    }

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        AtelierFileTreeRowView()
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard let outlineView = notification.object as? NSOutlineView,
              outlineView.selectedRow >= 0,
              let node = outlineView.item(atRow: outlineView.selectedRow) as? FileNode,
              !node.isDirectory else { return }
        onSelect(node.url)
    }

    @objc func handleSingleClick(_ recognizer: NSClickGestureRecognizer) {
        guard recognizer.state == .ended,
              let outlineView = recognizer.view as? NSOutlineView else { return }

        let location = recognizer.location(in: outlineView)
        let row = outlineView.row(at: location)
        guard row >= 0,
              let node = outlineView.item(atRow: row) as? FileNode else { return }

        if !node.isDirectory {
            let wasSelected = outlineView.selectedRow == row
            outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            if wasSelected {
                onSelect(node.url)
            }
            return
        }

        guard !outlineView.frameOfOutlineCell(atRow: row).contains(location) else { return }

        if outlineView.isItemExpanded(node) {
            outlineView.collapseItem(node)
        } else {
            outlineView.expandItem(node)
        }
    }

    private func loadChildren(_ node: FileNode) -> [FileNode] {
        guard node.isDirectory else { return [] }
        if let children = node.children { return children }

        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: node.url,
            includingPropertiesForKeys: keys,
            options: []
        )) ?? []

        let children = urls.compactMap { url -> FileNode? in
            guard !IgnoreRules.shouldIgnore(url) else { return nil }
            let values = try? url.resourceValues(forKeys: Set(keys))
            let isDirectory = values?.isDirectory == true && values?.isSymbolicLink != true
            return FileNode(url: url, isDirectory: isDirectory)
        }.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        node.children = children
        return children
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

    private func icon(for node: FileNode) -> NSImage? {
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

    private func iconColor(for node: FileNode) -> NSColor {
        if node.isDirectory { return AtelierNativePalette.accent }
        switch node.url.pathExtension.lowercased() {
        case "sh", "zsh", "bash": return NSColor.systemOrange
        case "swift": return NSColor.systemOrange
        default: return AtelierNativePalette.accent
        }
    }
}

private final class AtelierFileTreeRowView: NSTableRowView {
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        AtelierNativePalette.selection.setFill()
        NSBezierPath(
            roundedRect: bounds.insetBy(dx: 5, dy: 1),
            xRadius: 7,
            yRadius: 7
        ).fill()
    }
}
