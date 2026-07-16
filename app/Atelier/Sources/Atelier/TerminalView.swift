import SwiftUI
import SwiftTerm

struct TerminalView: NSViewRepresentable {
    @Environment(\.atelierZoomScale) private var scale

    let terminal: LocalProcessTerminalView

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        terminal
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        nsView.font = .monospacedSystemFont(ofSize: 13.5 * scale, weight: .regular)
        nsView.needsDisplay = true
        nsView.displayIfNeeded()
    }
}
