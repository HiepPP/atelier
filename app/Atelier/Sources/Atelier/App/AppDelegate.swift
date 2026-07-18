import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?

    private var watchdog: ResourceWatchdog?
    private var terminationTask: Task<Void, Never>?
    private var hasPreparedForTermination = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ResourceWatchdog.shouldRun() else { return }
        DefaultWatchdogResponder.requestNotificationAuthorization()
        let watchdog = ResourceWatchdog.makeDefault()
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
        watchdog?.stop()
        if terminationTask == nil, !hasPreparedForTermination {
            model?.stop()
        }
    }
}
