import SwiftUI
import SwiftTerm

final class AtelierTerminalNativeView: LocalProcessTerminalView {
    private var shouldFocusWhenAttached = false

    func requestFocusWhenAttached() {
        shouldFocusWhenAttached = true
        focusIfPossible()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        focusIfPossible()
    }

    private func focusIfPossible() {
        guard shouldFocusWhenAttached, let window else { return }
        shouldFocusWhenAttached = false
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else { return }
            window.makeFirstResponder(self)
        }
    }
}

struct TerminalView: NSViewRepresentable {
    let terminal: AtelierTerminalNativeView
    let scale: CGFloat

    func makeNSView(context: Context) -> AtelierTerminalNativeView {
        terminal.requestFocusWhenAttached()
        return terminal
    }

    func updateNSView(_ nsView: AtelierTerminalNativeView, context: Context) {
        let targetSize = 13.5 * scale
        guard abs(nsView.font.pointSize - targetSize) > 0.01 else { return }

        nsView.font = .monospacedSystemFont(ofSize: targetSize, weight: .regular)
        nsView.setNeedsDisplay(nsView.bounds)
        nsView.layoutSubtreeIfNeeded()
        nsView.displayIfNeeded()
    }
}
