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

struct ProjectCommandToolbarCenterBridge: NSViewRepresentable {
    let onCorrection: (CGFloat) -> Void

    func makeNSView(context: Context) -> ProjectCommandToolbarMarkerView {
        ProjectCommandToolbarMarkerView(frame: .zero, onCorrection: onCorrection)
    }

    func updateNSView(_ nsView: ProjectCommandToolbarMarkerView, context: Context) {
        nsView.onCorrection = onCorrection
        nsView.scheduleMeasurement()
    }
}

final class ProjectCommandToolbarMarkerView: NSView {
    var onCorrection: (CGFloat) -> Void
    private var measurementGeneration = 0

    init(frame frameRect: NSRect, onCorrection: @escaping (CGFloat) -> Void) {
        self.onCorrection = onCorrection
        super.init(frame: frameRect)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleMeasurement()
    }

    func scheduleMeasurement() {
        measurementGeneration += 1
        let generation = measurementGeneration
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, generation == measurementGeneration else { return }
            measureCorrection()
        }
    }

    private func measureCorrection() {
        guard let window, bounds.width > 0 else { return }
        let frameInWindow = convert(bounds, to: nil)
        let correction = ProjectCommandLayoutPolicy.toolbarCorrection(
            windowWidth: window.frame.width,
            itemFrame: frameInWindow
        )
        guard abs(correction) >= 0.5 else { return }
        onCorrection(correction)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}
