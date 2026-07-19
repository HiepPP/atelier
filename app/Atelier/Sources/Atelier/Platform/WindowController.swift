import AppKit
import KeyboardShortcuts

nonisolated enum WorkspaceResponderPolicy {
    static func canRestore(
        ownerWorkspaceID: String?,
        activeWorkspaceID: String?,
        capturedRevision: UInt64,
        currentRevision: UInt64
    ) -> Bool {
        ownerWorkspaceID != nil
            && ownerWorkspaceID == activeWorkspaceID
            && capturedRevision == currentRevision
    }
}

@MainActor
final class WindowController {
    var onScreenDidChange: (() -> Void)?

    private weak var workspaceWindow: NSWindow?
    private var shortcutInstalled = false
    private var activeWorkspaceID: String?
    private var responderRevision: UInt64 = 0
    private let responderOwners = NSMapTable<NSResponder, NSString>(
        keyOptions: .weakMemory,
        valueOptions: .strongMemory
    )

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
        let firstResponder = currentFirstResponder()
        workspaceWindow.zoom(nil)
        restoreFirstResponder(firstResponder)
    }

    func currentFirstResponder() -> NSResponder? {
        guard let responder = workspaceWindow?.firstResponder else { return nil }
        if let activeWorkspaceID {
            responderOwners.setObject(activeWorkspaceID as NSString, forKey: responder)
        }
        return responder
    }

    func setActiveWorkspace(id: String?) {
        guard id != activeWorkspaceID else { return }
        activeWorkspaceID = id
        responderRevision &+= 1
        workspaceWindow?.makeFirstResponder(nil)
    }

    func restoreFirstResponder(_ responder: NSResponder?) {
        guard let workspaceWindow, let responder else { return }
        let ownerWorkspaceID = responderOwners.object(forKey: responder) as String?
        let capturedRevision = responderRevision
        guard WorkspaceResponderPolicy.canRestore(
            ownerWorkspaceID: ownerWorkspaceID,
            activeWorkspaceID: activeWorkspaceID,
            capturedRevision: capturedRevision,
            currentRevision: responderRevision
        ) else { return }
        Task { @MainActor [weak workspaceWindow, weak responder] in
            await Task.yield()
            guard let workspaceWindow, let responder else { return }
            guard WorkspaceResponderPolicy.canRestore(
                ownerWorkspaceID: ownerWorkspaceID,
                activeWorkspaceID: activeWorkspaceID,
                capturedRevision: capturedRevision,
                currentRevision: responderRevision
            ) else { return }
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
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .line
        AppLogger.window.debug("Configured workspace window")
    }
}
