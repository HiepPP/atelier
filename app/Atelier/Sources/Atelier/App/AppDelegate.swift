import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?

    private var watchdog: ResourceWatchdog?
    private var terminationTask: Task<Void, Never>?
    private var hasPreparedForTermination = false
    private var visibilityObservers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let diagnosticsEnabled = RuntimeDiagnosticsService.shouldRun()
        let watchdogEnabled = ResourceWatchdog.shouldRun()
        if diagnosticsEnabled {
            RuntimeDiagnosticsService.shared.start(
                sampleInternally: !watchdogEnabled,
                mainSnapshotProvider: { [weak self] in
                    self?.model?.runtimeDiagnosticsSnapshot() ?? RuntimeMainSnapshot()
                },
                probeHandler: { [weak self] request in
                    guard let model = self?.model else {
                        let isMainProbe = request.command == .main
                        return RuntimeProbeResponse(
                            schemaVersion: 1,
                            id: request.id,
                            command: request.command,
                            status: isMainProbe ? "ok" : "notApplicable",
                            completedAt: Date().formatted(.iso8601),
                            elapsedMs: 0,
                            result: isMainProbe ? [
                                "timeout": .boolean(false),
                                "heartbeatAgeMs": .double(
                                    RuntimeDiagnosticsService.shared
                                        .currentHeartbeatAgeMilliseconds()
                                )
                            ] : [:],
                            editor: nil,
                            error: isMainProbe ? nil : "Application model is unavailable."
                        )
                    }
                    return await model.handleRuntimeProbe(request)
                }
            )
            observeApplicationVisibility()
            MenuBarPanelObserver.shared.startClickMonitor()
        }
        guard watchdogEnabled else { return }
        DefaultWatchdogResponder.requestNotificationAuthorization()
        let sampleObserver: (@Sendable (ProcessSample, Double) -> Void)?
        if diagnosticsEnabled {
            sampleObserver = { @Sendable (sample: ProcessSample, time: Double) in
                RuntimeDiagnosticsService.shared.consumeProcessSample(sample, at: time)
            }
        } else {
            sampleObserver = nil
        }
        let watchdog = ResourceWatchdog.makeDefault(
            sampleObserver: sampleObserver
        )
        self.watchdog = watchdog
        watchdog.start()
    }

    /// Diagnostics run off the main thread and cannot read AppKit state, so the
    /// delegate pushes window visibility changes into the service.
    private func observeApplicationVisibility() {
        let center = NotificationCenter.default
        let applicationNames: [Notification.Name] = [
            NSApplication.didHideNotification,
            NSApplication.didUnhideNotification,
            NSApplication.didChangeOcclusionStateNotification
        ]
        let windowNames: [Notification.Name] = [
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification,
            NSWindow.willCloseNotification,
            NSWindow.didBecomeKeyNotification
        ]
        visibilityObservers =
            applicationNames.map { name in
                center.addObserver(forName: name, object: NSApp, queue: .main) { _ in
                    MainActor.assumeIsolated { Self.publishApplicationVisibility() }
                }
            }
            + windowNames.map { name in
                center.addObserver(forName: name, object: nil, queue: .main) { _ in
                    MainActor.assumeIsolated { Self.publishApplicationVisibility() }
                }
            }
        // Never pause from a launch-time probe. SwiftUI creates the window after
        // this callback, and a window that never becomes key would leave pings
        // paused for the whole session. Publishing only a positive result keeps
        // the safe default (pinging) until a real hide or minimize arrives.
        Self.publishApplicationVisibility(publishesHiddenState: false)
        DispatchQueue.main.async {
            Self.publishApplicationVisibility(publishesHiddenState: false)
        }
    }

    /// Pings pause only when no window is on screen: the app is hidden, or every
    /// window is minimized or closed. A covered or inactive window still renders,
    /// and the heartbeat is the primary freeze signal while an agent or the user
    /// drives Atelier from a terminal, so pausing there would erase the evidence
    /// exactly when it is needed.
    private static func publishApplicationVisibility(publishesHiddenState: Bool = true) {
        let isVisible = !NSApp.isHidden && NSApp.windows.contains { $0.isVisible }
        guard isVisible || publishesHiddenState else { return }
        RuntimeDiagnosticsService.shared.setApplicationVisible(isVisible)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if hasPreparedForTermination { return .terminateNow }
        guard terminationTask == nil, let model else { return .terminateNow }
        let stopTask = model.stop()
        terminationTask = Task { @MainActor [weak self, weak sender] in
            await stopTask.value
            self?.hasPreparedForTermination = true
            self?.terminationTask = nil
            sender?.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        for observer in visibilityObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        visibilityObservers.removeAll(keepingCapacity: false)
        RuntimeDiagnosticsService.shared.stop()
        watchdog?.stop()
        if terminationTask == nil, !hasPreparedForTermination {
            model?.stop()
        }
    }
}
