import SwiftUI
import SwiftTerm

struct TerminalView: NSViewRepresentable {
    let terminal: LocalProcessTerminalView

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        terminal
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {}
}
