import AppKit
import Foundation

/// Counts how often the `MenuBarExtra` panel actually appears.
///
/// The snapshot writes once per second, so a panel that opens and closes inside
/// that second leaves no trace in a sampled read. These counters survive the
/// gap: they answer "did the panel ever show, and on which Space" without
/// needing the sample to land at the right instant.
@MainActor
final class MenuBarPanelObserver {
    static let shared = MenuBarPanelObserver()

    private(set) var shownCount = 0
    private(set) var hiddenCount = 0
    private(set) var lastShownOnActiveSpace: Bool?
    private(set) var lastShownWasKey: Bool?

    private(set) var statusItemClickCount = 0

    private var observation: NSKeyValueObservation?
    private weak var observedWindow: NSWindow?
    private var clickMonitor: Any?

    private init() {}

    /// Count clicks that land on the status item. A show counter alone cannot
    /// tell "the user never clicked" from "the click never opened the panel".
    /// The monitor returns every event untouched, so it changes no behavior.
    func startClickMonitor() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            guard event.window?.className.contains("StatusBarWindow") == true else {
                return event
            }
            MainActor.assumeIsolated {
                MenuBarPanelObserver.shared.recordStatusItemClick()
            }
            return event
        }
    }

    private func recordStatusItemClick() {
        statusItemClickCount += 1
        RuntimeDiagnosticsService.shared.record(
            category: "menuBar",
            name: "statusItemClick",
            metadata: ["clickCount": .integer(statusItemClickCount)]
        )
    }

    /// Attach once per panel window. SwiftUI keeps the window after a close, so
    /// the observation stays valid across open and close cycles.
    func observe(_ window: NSWindow) {
        guard observedWindow !== window else { return }
        observation?.invalidate()
        observedWindow = window
        observation = window.observe(\.isVisible, options: [.new]) { window, change in
            guard let isVisible = change.newValue else { return }
            MainActor.assumeIsolated {
                MenuBarPanelObserver.shared.recordVisibility(isVisible, of: window)
            }
        }
    }

    private func recordVisibility(_ isVisible: Bool, of window: NSWindow) {
        if isVisible {
            shownCount += 1
            lastShownOnActiveSpace = window.isOnActiveSpace
            lastShownWasKey = window.isKeyWindow
        } else {
            hiddenCount += 1
        }
        RuntimeDiagnosticsService.shared.record(
            category: "menuBar",
            name: isVisible ? "panelShown" : "panelHidden",
            metadata: [
                "onActiveSpace": .boolean(window.isOnActiveSpace),
                "isKeyWindow": .boolean(window.isKeyWindow),
                "level": .integer(window.level.rawValue)
            ]
        )
    }
}
