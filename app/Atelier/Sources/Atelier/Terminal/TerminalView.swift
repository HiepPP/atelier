import SwiftUI

struct TerminalView: View {
    let controller: TerminalController
    let scale: CGFloat
    let codeFontRevision: Int
    let isActive: Bool

    var body: some View {
        TerminalRepresentable(
            controller: controller,
            scale: scale,
            codeFontRevision: codeFontRevision,
            isActive: isActive
        )
        .padding(.horizontal, AtelierMetrics.spaceM)
        .padding(.vertical, AtelierMetrics.spaceS)
        .background(AtelierTheme.editor)
    }
}
