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
    private var revealTask: Task<Void, Never>?
    private var lastRevealRequestID: UUID?
    private var fileIconImages: [URL: NSImage] = [:]
    private var folderIconImages: [URL: MaterialFolderImages] = [:]
    private var contextMenuTarget: URL?
    private var contextMenuItem: FileTreeNode?
    private var diagnosticRootPath: String

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
        diagnosticRootPath = rootURL.standardizedFileURL.path
        self.ignoredPaths = FileTreeGitIgnorePresentation.normalized(ignoredPaths)
        self.onTargetDirectoryChange = onTargetDirectoryChange
        self.onCreateItem = onCreateItem
        self.onRenameItem = onRenameItem
        self.onMoveItemToTrash = onMoveItemToTrash
        self.onAddItemToGitIgnore = onAddItemToGitIgnore
        self.onPasteRelativePath = onPasteRelativePath
        self.onPreview = onPreview
        self.onOpen = onOpen
        super.init()
        RuntimeFileTreeMetricsStore.shared.register(
            rootPath: diagnosticRootPath,
            relativeRootName: rootURL.lastPathComponent
        )
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
        let normalizedIgnoredPaths = FileTreeGitIgnorePresentation.normalized(ignoredPaths)
        let ignoredPathsChanged = self.ignoredPaths != normalizedIgnoredPaths
        self.ignoredPaths = normalizedIgnoredPaths
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
            fileIconImages.removeAll(keepingCapacity: true)
            folderIconImages.removeAll(keepingCapacity: true)
            RuntimeFileTreeMetricsStore.shared.unregister(rootPath: diagnosticRootPath)
            root = FileTreeNode(url: rootURL, isDirectory: true)
            diagnosticRootPath = rootURL.standardizedFileURL.path
            RuntimeFileTreeMetricsStore.shared.register(
                rootPath: diagnosticRootPath,
                relativeRootName: rootURL.lastPathComponent
            )
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
        cachedFont = nil
        cachedRowHeight = nil
        guard let outlineView else { return }
        outlineView.rowHeight = rowHeight
        forEachVisibleCell(in: outlineView) { cell, _ in
            cell.textField?.font = font
        }
    }

    func stop() {
        revealTask?.cancel()
        revealTask = nil
        cancelLoads()
        RuntimeFileTreeMetricsStore.shared.unregister(rootPath: diagnosticRootPath)
        (outlineView as? FileTreeOutlineView)?.menuProvider = nil
        outlineView?.dataSource = nil
        outlineView?.delegate = nil
        outlineView?.target = nil
        outlineView?.doubleAction = nil
        outlineView = nil
    }

    func reveal(_ request: FileTreeRevealRequest?) {
        guard lastRevealRequestID != request?.id else { return }
        lastRevealRequestID = request?.id
        revealTask?.cancel()
        guard let request else {
            revealTask = nil
            return
        }
        revealTask = Task { [weak self] in
            await self?.revealFile(at: request.url)
        }
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
        cell.imageView?.contentTintColor = nil
        cell.setSymbolicLink(node.isSymbolicLink)
        let isIgnored = FileTreeGitIgnorePresentation.isIgnored(
            node.url,
            rootURL: root.url,
            ignoredPaths: ignoredPaths
        )
        cell.alphaValue = isIgnored ? 0.5 : 1
        cell.toolTip = nil
        cell.setAccessibilityHelp(isIgnored ? "Ignored by Git" : nil)
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        toolTipFor cell: NSCell,
        rect: NSRectPointer,
        tableColumn: NSTableColumn?,
        item: Any,
        mouseLocation: NSPoint
    ) -> String {
        guard let node = item as? FileTreeNode,
              FileTreeGitIgnorePresentation.isIgnored(
                  node.url,
                  rootURL: root.url,
                  ignoredPaths: ignoredPaths
              ) else { return "" }
        return "Ignored by Git"
    }

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        FileTreeRowView()
    }

    func outlineViewItemWillExpand(_ notification: Notification) {
        guard let node = notification.userInfo?["NSObject"] as? FileTreeNode else { return }
        load(node)
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        refreshIcon(for: notification)
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        refreshIcon(for: notification)
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
        guard let node = interactionNode(in: sender) else { return }
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
        guard let node = interactionNode(in: sender), !node.isDirectory else { return }
        onOpen(node.url)
    }

    private func interactionNode(in outlineView: NSOutlineView) -> FileTreeNode? {
        if let node = (outlineView as? FileTreeOutlineView)?.mouseDownItem as? FileTreeNode {
            return node
        }
        let row = outlineView.clickedRow >= 0 ? outlineView.clickedRow : outlineView.selectedRow
        guard row >= 0 else { return nil }
        return outlineView.item(atRow: row) as? FileTreeNode
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

    @discardableResult
    private func load(_ node: FileTreeNode) -> Task<Void, Never>? {
        if let task = loadTasks[node.url] { return task }
        let isInitialLoad = node.children == nil
        guard node.beginLoading() else { return nil }
        let url = node.url
        let isRootLoad = node === root
        let diagnosticRootPath = self.diagnosticRootPath
        if isRootLoad {
            RuntimeFileTreeMetricsStore.shared.loading(rootPath: diagnosticRootPath)
        }
        AppLogger.fileTree.debug("Loading directory: \(url.lastPathComponent, privacy: .public)")
        let task = Task { [weak self, weak node] in
            guard let self, let node else { return }
            do {
                let entries = try await service.children(of: url)
                guard !Task.isCancelled, node.url == url else { return }
                prewarmIcons(for: entries)
                let changed = node.apply(entries)
                if isRootLoad {
                    RuntimeFileTreeMetricsStore.shared.loaded(
                        rootPath: diagnosticRootPath,
                        entryCount: entries.count
                    )
                }
                AppLogger.fileTree.debug(
                    "Loaded \(entries.count) entries from \(url.lastPathComponent, privacy: .public)"
                )
                if changed || isInitialLoad {
                    reload(node, isInitialLoad: isInitialLoad)
                }
            } catch is CancellationError {
                return
            } catch {
                node.failLoading()
                if isRootLoad {
                    RuntimeFileTreeMetricsStore.shared.failed(rootPath: diagnosticRootPath)
                }
                AppLogger.fileTree.error("File tree load failed: \(error.localizedDescription, privacy: .public)")
                reload(node, isInitialLoad: isInitialLoad)
            }
            loadTasks[url] = nil
        }
        loadTasks[url] = task
        return task
    }

    private func revealFile(at url: URL) async {
        let targetURL = url.standardizedFileURL
        let rootURL = root.url.standardizedFileURL
        guard FileTreePathPolicy.contains(targetURL, within: rootURL),
              targetURL != rootURL else { return }

        let targetComponents = targetURL.pathComponents.dropFirst(rootURL.pathComponents.count)
        var node = root
        var expectedURL = rootURL

        for component in targetComponents {
            guard !Task.isCancelled else { return }
            expectedURL.appendPathComponent(component)
            await loadChildrenIfNeeded(node)
            guard !Task.isCancelled else { return }

            var child = node.children?.first {
                $0.url.standardizedFileURL == expectedURL.standardizedFileURL
            }
            if child == nil, let refreshTask = load(node) {
                await refreshTask.value
                guard !Task.isCancelled else { return }
                child = node.children?.first {
                    $0.url.standardizedFileURL == expectedURL.standardizedFileURL
                }
            }
            guard let child else { return }
            node = child
            if node.isDirectory {
                outlineView?.expandItem(node)
            }
        }

        guard !node.isDirectory, let outlineView else { return }
        let row = outlineView.row(forItem: node)
        guard row >= 0 else { return }
        outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        outlineView.scrollRowToVisible(row)
        outlineView.window?.makeFirstResponder(outlineView)
    }

    private func loadChildrenIfNeeded(_ node: FileTreeNode) async {
        guard node.children == nil, let task = load(node) else { return }
        await task.value
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
        forEachVisibleCell(in: outlineView) { cell, row in
            guard let node = outlineView.item(atRow: row) as? FileTreeNode,
                  let cell = cell as? FileTreeCellView else { return }
            configure(cell, for: node)
        }
    }

    private func forEachVisibleCell(
        in outlineView: NSOutlineView,
        _ body: (NSTableCellView, Int) -> Void
    ) {
        let visibleRows = outlineView.rows(in: outlineView.visibleRect)
        guard visibleRows.location != NSNotFound else { return }
        for row in visibleRows.location..<NSMaxRange(visibleRows) {
            guard let cell = outlineView.view(atColumn: 0, row: row, makeIfNecessary: false)
                as? NSTableCellView else { continue }
            body(cell, row)
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

    // Font and row height are read per cell; cache them and invalidate only
    // when scale or displayScale change.
    private var cachedFont: NSFont?
    private var font: NSFont {
        if let cachedFont { return cachedFont }
        let font = NSFont.systemFont(
            ofSize: AtelierFontScaling.snapped(
                AtelierTypography.uiSize * scale,
                displayScale: displayScale
            ),
            weight: .regular
        )
        cachedFont = font
        return font
    }

    private var cachedRowHeight: CGFloat?
    private var rowHeight: CGFloat {
        if let cachedRowHeight { return cachedRowHeight }
        let height = max(
            AtelierMetrics.rowHeight * scale,
            ceil(font.ascender - font.descender + font.leading + AtelierMetrics.spaceXS)
        )
        cachedRowHeight = height
        return height
    }

    private func makeCell(identifier: NSUserInterfaceItemIdentifier) -> FileTreeCellView {
        FileTreeCellView(identifier: identifier, font: font)
    }

    private func icon(for node: FileTreeNode) -> NSImage? {
        if node.isDirectory || node.symbolicLinkTargetIsDirectory {
            let images = folderIconImages[node.url]
            let isExpanded = outlineView?.isItemExpanded(node) == true
            if let images {
                return isExpanded ? images.expanded : images.closed
            }
            return MaterialFileIconStore.shared.cachedFolderImage(
                forPath: "",
                isExpanded: isExpanded
            )
        }
        return fileIconImages[node.url]
            ?? MaterialFileIconStore.shared.cachedFileImage(forPath: "")
    }

    private func prewarmIcons(for entries: [FileTreeEntry]) {
        let maximumIconCount = 16_384
        if fileIconImages.count + folderIconImages.count + entries.count > maximumIconCount {
            fileIconImages.removeAll(keepingCapacity: true)
            folderIconImages.removeAll(keepingCapacity: true)
        }
        let store = MaterialFileIconStore.shared
        for entry in entries {
            if entry.isDirectory || entry.symbolicLinkTargetIsDirectory {
                folderIconImages[entry.url] = store.prewarmFolder(path: entry.url.path)
            } else {
                fileIconImages[entry.url] = store.prewarmFile(path: entry.url.path)
            }
        }
    }

    private func refreshIcon(for notification: Notification) {
        guard let outlineView,
              let node = notification.userInfo?["NSObject"] as? FileTreeNode else { return }
        let row = outlineView.row(forItem: node)
        guard row >= 0,
              let cell = outlineView.view(atColumn: 0, row: row, makeIfNecessary: false)
                as? FileTreeCellView else { return }
        cell.imageView?.image = icon(for: node)
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
    private(set) var mouseDownItem: Any?

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let row = row(at: location)
        mouseDownItem = row >= 0 ? item(atRow: row) : nil
        defer { mouseDownItem = nil }

        guard row >= 0 else {
            super.mouseDown(with: event)
            return
        }

        window?.makeFirstResponder(self)
        selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        let isDirectory = (mouseDownItem as? FileTreeNode)?.isDirectory == true
        let clickAction = isDirectory || event.clickCount == 1 ? action : doubleAction
        _ = sendAction(clickAction, to: target)
    }

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

        let pointerIsInside: Bool
        if let window, window.isKeyWindow {
            let windowLocation = window.convertPoint(fromScreen: NSEvent.mouseLocation)
            pointerIsInside = visibleRect.contains(convert(windowLocation, from: nil))
        } else {
            pointerIsInside = false
        }
        if isHovering != pointerIsInside {
            isHovering = pointerIsInside
            needsDisplay = true
        }
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
