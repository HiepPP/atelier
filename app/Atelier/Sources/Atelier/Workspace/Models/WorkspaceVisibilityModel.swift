import AppKit
import Observation

/// One window's on-screen state, captured on the main actor so the policy stays
/// testable without AppKit.
nonisolated struct WorkspaceWindowVisibility: Sendable, Equatable {
    let isVisible: Bool
    let isKeyWindow: Bool
    let isOcclusionVisible: Bool
}

nonisolated enum WorkspaceOnScreenPolicy {
    /// True when at least one window can actually be seen.
    ///
    /// A key window counts as on screen even when its occlusion state lacks
    /// `.visible`. That bit desyncs: the terminal freeze investigation proved
    /// AppKit can report a maximized, actively-used key window as occluded (see
    /// `TerminalOcclusionRedrawPolicy`). Trusting the bit alone would stall
    /// polling while the user is looking at the result.
    static func isOnScreen(
        isApplicationHidden: Bool,
        windows: [WorkspaceWindowVisibility]
    ) -> Bool {
        guard !isApplicationHidden else { return false }
        return windows.contains { window in
            window.isVisible && (window.isKeyWindow || window.isOcclusionVisible)
        }
    }
}

/// Publishes whether any Atelier window is on screen, so repeating UI work can
/// stop while the app is hidden, minimized, or fully covered.
///
/// Separate from `RuntimeDiagnosticsService.isApplicationVisible`, which
/// deliberately keeps pinging through occlusion: a heartbeat must stay armed
/// exactly when a window is covered, because that is when a freeze goes
/// unnoticed. Presentation work has the opposite requirement.
@MainActor
@Observable
final class WorkspaceVisibilityModel {
    private(set) var isOnScreen = true

    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        let applicationNames: [Notification.Name] = [
            NSApplication.didHideNotification,
            NSApplication.didUnhideNotification,
            NSApplication.didChangeOcclusionStateNotification
        ]
        let windowNames: [Notification.Name] = [
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification,
            NSWindow.didChangeOcclusionStateNotification,
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification
        ]
        observers =
            applicationNames.map { name in
                center.addObserver(forName: name, object: NSApp, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.update() }
                }
            }
            + windowNames.map { name in
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.update() }
                }
            }
        // `willClose` fires while the window is still in `NSApp.windows` and
        // still reports `isVisible`, so the closing window is excluded by hand.
        observers.append(
            center.addObserver(
                forName: NSWindow.willCloseNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let closing = notification.object as? NSWindow
                MainActor.assumeIsolated { self?.update(closingWindow: closing) }
            }
        )
        update()
    }

    func stop() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll(keepingCapacity: false)
        // Never leave consumers parked on a stale `false`: a stopped model must
        // not be the reason a restarted poll refuses to run.
        isOnScreen = true
    }

    private func update(closingWindow: NSWindow? = nil) {
        let windows = NSApp.windows
            .filter { $0 !== closingWindow }
            .map { window in
                WorkspaceWindowVisibility(
                    isVisible: window.isVisible,
                    isKeyWindow: window.isKeyWindow,
                    isOcclusionVisible: window.occlusionState.contains(.visible)
                )
            }
        let next = WorkspaceOnScreenPolicy.isOnScreen(
            isApplicationHidden: NSApp.isHidden,
            windows: windows
        )
        guard next != isOnScreen else { return }
        isOnScreen = next
    }

    isolated deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
