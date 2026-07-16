import AppKit
import SwiftUI

struct WorkspaceWindowBridge: NSViewRepresentable {
    let controller: WindowController

    func makeNSView(context: Context) -> WorkspaceWindowMarkerView {
        WorkspaceWindowMarkerView(controller: controller)
    }

    func updateNSView(_ nsView: WorkspaceWindowMarkerView, context: Context) {
        nsView.controller = controller
        controller.track(nsView.window)
    }
}

final class WorkspaceWindowMarkerView: NSView {
    weak var controller: WindowController?

    init(controller: WindowController) {
        self.controller = controller
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        controller?.track(window)
    }
}
