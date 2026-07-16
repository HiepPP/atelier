import AppKit
import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    static let showAtelier = Self("showAtelier")
}

enum AtelierShortcuts {
    private static weak var workspaceWindow: NSWindow?

    @MainActor
    static func install() {
        KeyboardShortcuts.onKeyUp(for: .showAtelier) {
            Task { @MainActor in
                showWorkspaceWindow()
            }
        }
    }

    @MainActor
    static func showWorkspaceWindow() {
        guard let workspaceWindow else { return }
        NSApp.activate(ignoringOtherApps: true)
        workspaceWindow.makeKeyAndOrderFront(nil)
    }

    @MainActor
    static func trackWorkspaceWindow(_ window: NSWindow?) {
        guard let window else { return }
        workspaceWindow = window
    }

    @MainActor
    static func zoomWorkspaceWindow() {
        workspaceWindow?.zoom(nil)
    }

    @MainActor
    static func maximizeWorkspaceWindow() {
        guard let workspaceWindow, !workspaceWindow.isZoomed else { return }
        workspaceWindow.zoom(nil)
    }
}

private final class AtelierWorkspaceWindowMarkerView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        AtelierShortcuts.trackWorkspaceWindow(window)
    }
}

struct AtelierWorkspaceWindowMarker: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        AtelierWorkspaceWindowMarkerView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        AtelierShortcuts.trackWorkspaceWindow(nsView.window)
    }
}

struct AtelierShortcutRecorder: View {
    var body: some View {
        KeyboardShortcuts.Recorder(
            "Show Atelier:",
            name: .showAtelier
        )
    }
}
