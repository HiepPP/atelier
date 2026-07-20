import AppKit

@MainActor
final class FileTreeController: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
    private let service = FileTreeService()
    private var root: FileTreeNode
    private var ignoredPaths: Set<String>
    private var onTargetDirectoryChange: (URL) -> Void
    private var onCreateItem: (FileTreeCreationKind, URL) -> Void
    private var onRenameItem: (URL, String) -> Void
    private var onMoveItemToTrash: (URL) -> Void
    private var onAddItemToGitIgnore: (URL) -> Void
    private var onPasteRelativePath: (String) -> Bool
    private var onPreview: (URL) -> Void
    private var onOpen: (URL) -> Void
    private var scale: CGFloat = 1
    private var displayScale: CGFloat = 2
    private var revision = 0
    private weak var outlineView: NSOutlineView?
    private var loadTasks: [URL: Task<Void, Never>] = [:]
    private var contextMenuTarget: URL?
    private var contextMenuItem: FileTreeNode?

    init(
        rootURL: URL,
        ignoredPaths: Set<String>,
        onTargetDirectoryChange: @escaping (URL) -> Void,
        onCreateItem: @escaping (FileTreeCreationKind, URL) -> Void,
        onRenameItem: @escaping (URL, String) -> Void,
        onMoveItemToTrash: @escaping (URL) -> Void,
        onAddItemToGitIgnore: @escaping (URL) -> Void,
        onPasteRelativePath: @escaping (String) -> Bool,
        onPreview: @escaping (URL) -> Void,
        onOpen: @escaping (URL) -> Void
    ) {
        root = FileTreeNode(url: rootURL, isDirectory: true)
        self.ignoredPaths = ignoredPaths
        self.onTargetDirectoryChange = onTargetDirectoryChange
        self.onCreateItem = onCreateItem
        self.onRenameItem = onRenameItem
        self.onMoveItemToTrash = onMoveItemToTrash
        self.onAddItemToGitIgnore = onAddItemToGitIgnore
        self.onPasteRelativePath = onPasteRelativePath
        self.onPreview = onPreview
        self.onOpen = onOpen
    }

    func makeView(scale: CGFloat, displayScale: CGFloat) -> NSScrollView {
        self.scale = scale
        self.displayScale = displayScale

        let outlineView = FileTreeOutlineView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("File"))
        column.title = "Files"
        column.minWidth = 160
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        outlineView.autoresizingMask = [.width]
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
        outlineView.action = #selector(handlePreview(_:))
        outlineView.doubleAction = #selector(handleOpen(_:))
        outlineView.menuProvider = { [weak self, weak outlineView] row in
            guard let self, let outlineView else { return nil }
            return self.contextMenu(for: row, in: outlineView)
        }
        self.outlineView = outlineView

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.scrollerStyle = .overlay
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
        ignoredPaths: Set<String>,
        scale: CGFloat,
        displayScale: CGFloat,
        onTargetDirectoryChange: @escaping (URL) -> Void,
        onCreateItem: @escaping (FileTreeCreationKind, URL) -> Void,
        onRenameItem: @escaping (URL, String) -> Void,
        onMoveItemToTrash: @escaping (URL) -> Void,
        onAddItemToGitIgnore: @escaping (URL) -> Void,
        onPasteRelativePath: @escaping (String) -> Bool,
        onPreview: @escaping (URL) -> Void,
        onOpen: @escaping (URL) -> Void
    ) {
        let ignoredPathsChanged = self.ignoredPaths != ignoredPaths
        self.ignoredPaths = ignoredPaths
        self.onTargetDirectoryChange = onTargetDirectoryChange
        self.onCreateItem = onCreateItem
        self.onRenameItem = onRenameItem
        self.onMoveItemToTrash = onMoveItemToTrash
        self.onAddItemToGitIgnore = onAddItemToGitIgnore
        self.onPasteRelativePath = onPasteRelativePath
        self.onPreview = onPreview
        self.onOpen = onOpen
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

        if ignoredPathsChanged { refreshVisibleCells() }

        guard self.scale != scale || self.displayScale != displayScale else { return }
        self.scale = scale
        self.displayScale = displayScale
        guard let outlineView else { return }
        outlineView.rowHeight = rowHeight
        for row in 0..<outlineView.numberOfRows {
            let cell = outlineView.view(atColumn: 0, row: row, makeIfNecessary: false)
                as? NSTableCellView
            cell?.textField?.font = font
        }
    }

    func stop() {
        cancelLoads()
        (outlineView as? FileTreeOutlineView)?.menuProvider = nil
        outlineView?.dataSource = nil
        outlineView?.delegate = nil
        outlineView?.target = nil
        outlineView?.doubleAction = nil
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
        let cell = (outlineView.makeView(withIdentifier: identifier, owner: nil) as? FileTreeCellView)
            ?? makeCell(identifier: identifier)
        configure(cell, for: node)
        return cell
    }

    private func configure(_ cell: FileTreeCellView, for node: FileTreeNode) {
        cell.textField?.stringValue = node.name
        cell.textField?.font = font
        cell.textField?.textColor = AppKitThemeAdapter.fileTreeForeground
        cell.imageView?.image = icon(for: node)
        cell.imageView?.contentTintColor = iconColor(for: node)
        cell.setSymbolicLink(node.isSymbolicLink)
        let isIgnored = FileTreeGitIgnorePresentation.isIgnored(
            node.url,
            rootURL: root.url,
            ignoredPaths: ignoredPaths
        )
        cell.alphaValue = isIgnored ? 0.5 : 1
        cell.toolTip = isIgnored ? "Ignored by Git" : nil
        cell.setAccessibilityHelp(isIgnored ? "Ignored by Git" : nil)
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

    @objc private func handlePreview(_ sender: NSOutlineView) {
        let row = sender.clickedRow >= 0 ? sender.clickedRow : sender.selectedRow
        guard row >= 0,
              let node = sender.item(atRow: row) as? FileTreeNode else { return }
        if NSApp.currentEvent?.modifierFlags.contains(.command) == true,
           let relativePath = FileTreePathPolicy.relativePath(of: node.url, within: root.url),
           onPasteRelativePath(FileTreePathPolicy.terminalReference(for: relativePath)) {
            return
        }
        if node.isDirectory {
            sender.isItemExpanded(node) ? sender.collapseItem(node) : sender.expandItem(node)
        } else {
            onPreview(node.url)
        }
    }

    @objc private func handleOpen(_ sender: NSOutlineView) {
        guard sender.clickedRow >= 0,
              let node = sender.item(atRow: sender.clickedRow) as? FileTreeNode,
              !node.isDirectory else { return }
        onOpen(node.url)
    }

    @objc private func createFileFromMenu(_ sender: NSMenuItem) {
        guard let contextMenuTarget else { return }
        onCreateItem(.file, contextMenuTarget)
    }

    @objc private func createFolderFromMenu(_ sender: NSMenuItem) {
        guard let contextMenuTarget else { return }
        onCreateItem(.folder, contextMenuTarget)
    }

    @objc private func renameItemFromMenu(_ sender: NSMenuItem) {
        guard let node = contextMenuItem,
              let window = outlineView?.window else { return }
        let field = NSTextField(string: node.name)
        field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)

        let alert = NSAlert()
        alert.messageText = "Rename \(node.name)"
        alert.informativeText = "Enter a new name for this item."
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name != node.name else { return }
            self?.onRenameItem(node.url, name)
        }
    }

    @objc private func moveItemToTrashFromMenu(_ sender: NSMenuItem) {
        guard let node = contextMenuItem,
              let window = outlineView?.window else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Move \(node.name) to Trash?"
        alert.informativeText = "This item can be recovered from Trash."
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.onMoveItemToTrash(node.url)
        }
    }

    @objc private func copyPathFromMenu(_ sender: NSMenuItem) {
        guard let node = contextMenuItem else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(node.url.path, forType: .string)
    }

    @objc private func addItemToGitIgnoreFromMenu(_ sender: NSMenuItem) {
        guard let node = contextMenuItem,
              node.name != ".gitignore",
              !FileTreeGitIgnorePresentation.isIgnored(
                  node.url,
                  rootURL: root.url,
                  ignoredPaths: ignoredPaths
              ) else { return }
        onAddItemToGitIgnore(node.url)
    }

    private func contextMenu(for row: Int, in outlineView: NSOutlineView) -> NSMenu? {
        let node: FileTreeNode?
        let target: URL
        if row < 0 {
            node = nil
            target = root.url
        } else {
            guard let item = outlineView.item(atRow: row) as? FileTreeNode else { return nil }
            node = item
            target = item.isDirectory
                ? item.url
                : ((outlineView.parent(forItem: item) as? FileTreeNode)?.url ?? root.url)
            outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        contextMenuItem = node
        contextMenuTarget = target
        onTargetDirectoryChange(target)

        let menu = NSMenu(title: "Explorer")
        menu.autoenablesItems = false
        if node?.isDirectory != false {
            menu.addItem(menuItem(
                title: "New File...",
                symbol: "doc.badge.plus",
                action: #selector(createFileFromMenu(_:))
            ))
            menu.addItem(menuItem(
                title: "New Folder...",
                symbol: "folder.badge.plus",
                action: #selector(createFolderFromMenu(_:))
            ))
        }

        if let node {
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            menu.addItem(menuItem(
                title: "Rename...",
                symbol: "pencil",
                action: #selector(renameItemFromMenu(_:))
            ))
            menu.addItem(menuItem(
                title: "Copy Path",
                symbol: "doc.on.doc",
                action: #selector(copyPathFromMenu(_:))
            ))
            let addToGitIgnore = menuItem(
                title: "Add to .gitignore",
                symbol: "eye.slash",
                action: #selector(addItemToGitIgnoreFromMenu(_:))
            )
            addToGitIgnore.isEnabled = node.name != ".gitignore"
                && !FileTreeGitIgnorePresentation.isIgnored(
                    node.url,
                    rootURL: root.url,
                    ignoredPaths: ignoredPaths
                )
            menu.addItem(addToGitIgnore)
            menu.addItem(.separator())
            menu.addItem(menuItem(
                title: "Move to Trash",
                symbol: "trash",
                action: #selector(moveItemToTrashFromMenu(_:))
            ))
        }
        return menu
    }

    private func menuItem(
        title: String,
        symbol: String,
        action: Selector
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return item
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

    private func refreshVisibleCells() {
        guard let outlineView else { return }
        for row in 0..<outlineView.numberOfRows {
            guard let node = outlineView.item(atRow: row) as? FileTreeNode,
                  let cell = outlineView.view(
                      atColumn: 0,
                      row: row,
                      makeIfNecessary: false
                  ) as? FileTreeCellView else { continue }
            configure(cell, for: node)
        }
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
        max(
            AtelierMetrics.rowHeight * scale,
            ceil(font.ascender - font.descender + font.leading + AtelierMetrics.spaceXS)
        )
    }

    private func makeCell(identifier: NSUserInterfaceItemIdentifier) -> FileTreeCellView {
        FileTreeCellView(identifier: identifier, font: font)
    }

    private func icon(for node: FileTreeNode) -> NSImage? {
        let symbol: String
        if node.isDirectory || node.symbolicLinkTargetIsDirectory {
            symbol = "folder"
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
        node.isDirectory || node.symbolicLinkTargetIsDirectory
            ? AppKitThemeAdapter.accent
            : AppKitThemeAdapter.secondary
    }
}

private final class FileTreeCellView: NSTableCellView {
    private let symbolicLinkBadge = NSImageView()
    private var badgeWidthConstraint: NSLayoutConstraint!
    private var badgeSpacingConstraint: NSLayoutConstraint!

    init(identifier: NSUserInterfaceItemIdentifier, font: NSFont) {
        super.init(frame: .zero)
        self.identifier = identifier

        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.imageScaling = .scaleProportionallyUpOrDown

        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.controlSize = .regular
        label.font = font
        label.lineBreakMode = .byTruncatingMiddle
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        symbolicLinkBadge.translatesAutoresizingMaskIntoConstraints = false
        symbolicLinkBadge.image = NSImage(
            systemSymbolName: "arrow.turn.up.right",
            accessibilityDescription: "Symbolic link"
        )
        symbolicLinkBadge.imageScaling = .scaleProportionallyDown
        symbolicLinkBadge.contentTintColor = AppKitThemeAdapter.secondary

        imageView = icon
        textField = label
        addSubview(icon)
        addSubview(label)
        addSubview(symbolicLinkBadge)

        badgeWidthConstraint = symbolicLinkBadge.widthAnchor.constraint(equalToConstant: 0)
        badgeSpacingConstraint = symbolicLinkBadge.leadingAnchor.constraint(
            equalTo: label.trailingAnchor
        )
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: AtelierMetrics.spaceXS
            ),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: AtelierMetrics.spaceL),
            icon.heightAnchor.constraint(equalToConstant: AtelierMetrics.spaceL),
            label.leadingAnchor.constraint(
                equalTo: icon.trailingAnchor,
                constant: AtelierMetrics.spaceXS
            ),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            badgeSpacingConstraint,
            badgeWidthConstraint,
            symbolicLinkBadge.heightAnchor.constraint(equalToConstant: AtelierTypography.micro),
            symbolicLinkBadge.centerYAnchor.constraint(equalTo: centerYAnchor),
            symbolicLinkBadge.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAnchor,
                constant: -AtelierMetrics.spaceXS
            )
        ])
        setSymbolicLink(false)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            textField?.textColor = AppKitThemeAdapter.fileTreeForeground
        }
    }

    func setSymbolicLink(_ isSymbolicLink: Bool) {
        symbolicLinkBadge.isHidden = !isSymbolicLink
        badgeSpacingConstraint.constant = isSymbolicLink ? AtelierMetrics.spaceXS : 0
        badgeWidthConstraint.constant = isSymbolicLink ? AtelierTypography.micro : 0
    }
}

private final class FileTreeOutlineView: NSOutlineView {
    var menuProvider: ((Int) -> NSMenu?)?

    override func resetCursorRects() {
        super.resetCursorRects()
        let visibleRows = rows(in: visibleRect)
        guard visibleRows.location != NSNotFound else { return }
        for row in visibleRows.location..<NSMaxRange(visibleRows) {
            addCursorRect(rect(ofRow: row).intersection(visibleRect), cursor: .pointingHand)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let location = convert(event.locationInWindow, from: nil)
        return menuProvider?(row(at: location))
    }
}

private final class FileTreeRowView: NSTableRowView {
    private let selectionEffect = FileTreeSelectionEffectView()
    private var hoverTrackingArea: NSTrackingArea?
    private var isHovering = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureSelectionEffect()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureSelectionEffect()
    }

    override var isSelected: Bool {
        didSet {
            selectionEffect.isHidden = !isSelected
        }
    }

    override func layout() {
        super.layout()
        selectionEffect.frame = selectionRect
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateSelectionTint()
    }

    override func updateTrackingAreas() {
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        needsDisplay = true
    }

    override func drawBackground(in dirtyRect: NSRect) {
        guard isHovering, !isSelected else { return }
        AppKitThemeAdapter.hover.setFill()
        rowShape.fill()
    }

    override func drawSelection(in dirtyRect: NSRect) {
        // Selection is rendered by the material view behind the cell content.
    }

    private func configureSelectionEffect() {
        selectionEffect.material = .underWindowBackground
        selectionEffect.blendingMode = .withinWindow
        selectionEffect.state = .followsWindowActiveState
        selectionEffect.isHidden = true
        selectionEffect.wantsLayer = true
        selectionEffect.layer?.cornerRadius = AtelierTheme.rowRadius
        selectionEffect.layer?.masksToBounds = true
        addSubview(selectionEffect, positioned: .below, relativeTo: nil)
        updateSelectionTint()
    }

    private func updateSelectionTint() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            selectionEffect.layer?.backgroundColor = AppKitThemeAdapter.accent
                .withAlphaComponent(0.16)
                .cgColor
        }
    }

    private var rowShape: NSBezierPath {
        NSBezierPath(
            roundedRect: selectionRect,
            xRadius: AtelierTheme.rowRadius,
            yRadius: AtelierTheme.rowRadius
        )
    }

    private var selectionRect: NSRect {
        bounds.insetBy(dx: AtelierMetrics.spaceXS, dy: 2)
    }
}

private final class FileTreeSelectionEffectView: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
