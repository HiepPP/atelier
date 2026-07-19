import SwiftTerm
import SwiftUI

struct TerminalRepresentable: NSViewRepresentable {
    @Environment(\.displayScale) private var displayScale

    let controller: TerminalController
    let scale: CGFloat
    let isActive: Bool

    func makeNSView(context: Context) -> AtelierTerminalNativeView {
        controller.attach(isActive: isActive)
    }

    func updateNSView(_ nsView: AtelierTerminalNativeView, context: Context) {
        controller.setActive(isActive)
        controller.updateScale(scale, displayScale: displayScale)
    }
}
