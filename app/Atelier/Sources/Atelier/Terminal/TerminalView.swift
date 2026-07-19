import SwiftUI

struct TerminalView: View {
    let controller: TerminalController
    let scale: CGFloat
    let isActive: Bool

    var body: some View {
        TerminalRepresentable(
            controller: controller,
            scale: scale,
            isActive: isActive
        )
    }
}
