import SwiftTerm
import SwiftUI

struct TerminalRepresentable: NSViewRepresentable {
    @Environment(\.displayScale) private var displayScale

    let controller: TerminalController
    let scale: CGFloat

    func makeNSView(context: Context) -> AtelierTerminalNativeView {
        controller.attach()
    }

    func updateNSView(_ nsView: AtelierTerminalNativeView, context: Context) {
        controller.updateScale(scale, displayScale: displayScale)
    }
}
