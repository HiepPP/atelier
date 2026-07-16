import AppKit
import KeyboardShortcuts

@MainActor
final class WindowController {
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
        workspaceWindow = window
        configure(window)
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
            workspaceWindow.makeFirstResponder(responder)
        }
    }

    private func configure(_ window: NSWindow) {
        window.backgroundColor = AppKitThemeAdapter.chrome
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        AppLogger.window.debug("Configured workspace window")
    }
}
