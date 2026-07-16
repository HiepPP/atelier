import AppKit
import SwiftUI
import SwiftTerm

struct TerminalView: View {
    let terminal: LocalProcessTerminalView
    let scale: CGFloat

    var body: some View {
        ZStack {
            AtelierTheme.editor

            TerminalRepresentable(terminal: terminal)
        }
        .task(id: scale) {
            updateFont()
        }
    }

    @MainActor
    private func updateFont() {
        let targetSize = 13.5 * scale
        guard abs(terminal.font.pointSize - targetSize) > 0.01 else { return }

        terminal.font = .monospacedSystemFont(ofSize: targetSize, weight: .regular)
        terminal.setNeedsDisplay(terminal.bounds)
        terminal.layoutSubtreeIfNeeded()
        terminal.displayIfNeeded()
    }
}

private struct TerminalRepresentable: NSViewRepresentable {
    let terminal: LocalProcessTerminalView

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        terminal
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {}
}
