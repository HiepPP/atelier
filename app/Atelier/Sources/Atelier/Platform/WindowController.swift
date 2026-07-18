import AppKit
import KeyboardShortcuts

@MainActor
final class WindowController {
    var onScreenDidChange: (() -> Void)?

    private weak var workspaceWindow: NSWindow?
    private var shortcutInstalled = false

    func installGlobalShortcut() {
        guard !shortcutInstalled else { return }
        shortcutInstalled = true
        KeyboardShortcuts.onKeyUp(for: .showAtelier) { [weak self] in
            Task { @MainActor in
                self?.showWorkspaceWindow()
            }
        }
    }

    func track(_ window: NSWindow?) {
        guard let window else { return }
        let changed = workspaceWindow !== window
        workspaceWindow = window
        guard changed else { return }
        configure(window)
        onScreenDidChange?()
    }

    func currentScreen() -> NSScreen? {
        workspaceWindow?.screen ?? NSScreen.main
    }

    func showWorkspaceWindow() {
        guard let workspaceWindow else { return }
        NSApp.activate(ignoringOtherApps: true)
        workspaceWindow.makeKeyAndOrderFront(nil)
    }

    func zoomWorkspaceWindow() {
        workspaceWindow?.zoom(nil)
    }

    func maximizeWorkspaceWindow() {
        guard let workspaceWindow, !workspaceWindow.isZoomed else { return }
        let firstResponder = workspaceWindow.firstResponder
        workspaceWindow.zoom(nil)
        restoreFirstResponder(firstResponder)
    }

    func currentFirstResponder() -> NSResponder? {
        workspaceWindow?.firstResponder
    }

    func restoreFirstResponder(_ responder: NSResponder?) {
        guard let workspaceWindow, let responder else { return }
        Task { @MainActor [weak workspaceWindow, weak responder] in
            await Task.yield()
            guard let workspaceWindow, let responder else { return }
            guard Self.responder(responder, belongsTo: workspaceWindow) else { return }
            workspaceWindow.makeFirstResponder(responder)
        }
    }

    private static func responder(_ responder: NSResponder, belongsTo window: NSWindow) -> Bool {
        var current: NSResponder? = responder
        var visited: Set<ObjectIdentifier> = []

        while let candidate = current {
            let identifier = ObjectIdentifier(candidate)
            guard visited.insert(identifier).inserted else { return false }
            if candidate === window { return true }
            if let view = candidate as? NSView, view.window === window { return true }
            current = candidate.nextResponder
        }
        return false
    }

    private func configure(_ window: NSWindow) {
        window.backgroundColor = AppKitThemeAdapter.chrome
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.titlebarSeparatorStyle = .automatic
        AppLogger.window.debug("Configured workspace window")
    }
}
