import SwiftUI
import AppKit

struct FileTreeView: NSViewRepresentable {
    let rootURL: URL
    let onSelect: (URL) -> Void

    func makeCoordinator() -> FileTreeCoordinator {
        FileTreeCoordinator(rootURL: rootURL, onSelect: onSelect)
    }

    func makeNSView(context: Context) -> NSScrollView {
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
        outlineView.backgroundColor = AtelierNativePalette.sidebar
        outlineView.selectionHighlightStyle = .regular
        outlineView.dataSource = context.coordinator
        outlineView.delegate = context.coordinator
        let clickRecognizer = NSClickGestureRecognizer(
            target: context.coordinator,
            action: #selector(FileTreeCoordinator.handleSingleClick(_:))
        )
        outlineView.addGestureRecognizer(clickRecognizer)
        outlineView.reloadData()
        outlineView.expandItem(context.coordinator.root)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = AtelierNativePalette.sidebar
        scrollView.documentView = outlineView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let outlineView = scrollView.documentView as? NSOutlineView else { return }
        if context.coordinator.root.url != rootURL {
            context.coordinator.reset(rootURL: rootURL)
            outlineView.reloadData()
            outlineView.expandItem(context.coordinator.root)
        }
    }
}
