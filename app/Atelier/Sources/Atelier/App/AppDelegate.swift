import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?

    private var watchdog: ResourceWatchdog?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ResourceWatchdog.shouldRun() else { return }
        DefaultWatchdogResponder.requestNotificationAuthorization()
        let watchdog = ResourceWatchdog.makeDefault()
        self.watchdog = watchdog
        watchdog.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        watchdog?.stop()
        model?.stop()
    }
}
