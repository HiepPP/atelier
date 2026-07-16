import AppKit
import SwiftUI

struct FileTreeRepresentable: NSViewRepresentable {
    @Environment(\.atelierZoomScale) private var scale

    let rootURL: URL
    let revision: Int
    let onSelect: (URL) -> Void

    func makeCoordinator() -> FileTreeController {
        FileTreeController(rootURL: rootURL, onSelect: onSelect)
    }

    func makeNSView(context: Context) -> NSScrollView {
        context.coordinator.makeView(scale: scale)
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.update(
            rootURL: rootURL,
            revision: revision,
            scale: scale,
            onSelect: onSelect
        )
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: FileTreeController) {
        coordinator.stop()
    }
}
