import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?

    private var watchdog: ResourceWatchdog?
    private var terminationTask: Task<Void, Never>?
    private var hasPreparedForTermination = false

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
        RuntimeDiagnosticsService.shared.stop()
        watchdog?.stop()
        if terminationTask == nil, !hasPreparedForTermination {
            model?.stop()
        }
    }
}
