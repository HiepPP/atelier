import Foundation
import UserNotifications

nonisolated protocol WatchdogResponder: Sendable {
    func respond(to breach: WatchdogBreach)
}

/// Background watchdog that samples this process's CPU and memory and, on a sustained
/// breach, hands off to a responder. Runs entirely off the main thread so it still
/// fires when the UI is wedged.
nonisolated final class ResourceWatchdog: @unchecked Sendable {
    private let sampler: ProcessMetricsSampling
    private let responder: WatchdogResponder
    private let interval: TimeInterval
    private let queue = DispatchQueue(label: "app.atelier.watchdog", qos: .utility)

    private var evaluator: WatchdogEvaluator
    private var timer: DispatchSourceTimer?
    private var hasFired = false

    init(
        sampler: ProcessMetricsSampling,
        responder: WatchdogResponder,
        thresholds: WatchdogThresholds = .default,
        interval: TimeInterval = 1
    ) {
        self.sampler = sampler
        self.responder = responder
        self.evaluator = WatchdogEvaluator(thresholds: thresholds)
        self.interval = interval
    }

    func start() {
        queue.async { [self] in
            guard timer == nil else { return }
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .now() + interval, repeating: interval)
            source.setEventHandler { [self] in tick() }
            timer = source
            source.resume()
        }
    }

    func stop() {
        queue.async { [self] in
            timer?.cancel()
            timer = nil
        }
    }

    private func tick() {
        guard !hasFired else { return }
        let sample = sampler.sample()
        let now = Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
        guard let breach = evaluator.evaluate(sample, at: now) else { return }
        hasFired = true
        timer?.cancel()
        timer = nil
        responder.respond(to: breach)
    }
}

extension ResourceWatchdog {
    static func makeDefault(thresholds: WatchdogThresholds = .default) -> ResourceWatchdog {
        ResourceWatchdog(
            sampler: ProcessMetrics(),
            responder: DefaultWatchdogResponder(),
            thresholds: thresholds
        )
    }

    /// Whether the safety gate should run this launch: honors the disable env var,
    /// the settings toggle (default on), and the self-test mode.
    static func shouldRun(
        arguments: [String] = CommandLine.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaults: UserDefaults = .standard
    ) -> Bool {
        if arguments.contains("--selftest") { return false }
        if environment["ATELIER_DISABLE_WATCHDOG"] == "1" { return false }
        if defaults.object(forKey: settingsKey) == nil { return true }
        return defaults.bool(forKey: settingsKey)
    }

    static let settingsKey = "resourceWatchdogEnabled"
}

/// Default breach handling: log, persist a marker, notify, then force-exit.
nonisolated struct DefaultWatchdogResponder: WatchdogResponder {
    /// Grace period before exit so the notification daemon can pick up the request.
    private static let exitGrace: TimeInterval = 0.4

    func respond(to breach: WatchdogBreach) {
        let record = ResourceExitRecord(breach: breach, occurredAt: Date())
        AppLogger.app.critical(
            "Resource watchdog force-exit: \(record.detail, privacy: .public)"
        )
        if let url = ResourceExitMarker.defaultURL() {
            ResourceExitMarker.write(record, to: url)
        }
        postNotification(record)
        Thread.sleep(forTimeInterval: Self.exitGrace)
        exit(EXIT_FAILURE)
    }

    static func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .provisional]) { _, _ in }
    }

    private func postNotification(_ record: ResourceExitRecord) {
        let content = UNMutableNotificationContent()
        content.title = record.reason == .memory
            ? "Atelier hit its memory limit"
            : "Atelier hit its CPU limit"
        content.body = "\(record.detail) Atelier quit to protect your Mac."
        let request = UNNotificationRequest(
            identifier: "app.atelier.watchdog",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
