import SwiftUI

struct TerminalView: View {
    let controller: TerminalController
    let scale: CGFloat

    var body: some View {
        TerminalRepresentable(controller: controller, scale: scale)
    }
}
