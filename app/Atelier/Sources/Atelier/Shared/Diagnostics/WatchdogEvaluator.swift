import Foundation

nonisolated struct WatchdogThresholds: Sendable, Equatable {
    /// Fire when the memory footprint reaches this many bytes.
    var memoryLimitBytes: UInt64
    /// Fire when sustained CPU use reaches this fraction of one core (1.0 == 100% of one core).
    var cpuCoreFraction: Double
    /// How long CPU must stay at or above the fraction before firing, in seconds.
    var cpuSustainSeconds: Double

    /// The CPU gate never fired before `ProcessMetrics` started converting mach
    /// ticks correctly, so it was calibrated against a reading about 42x too
    /// low. Measured on a normal launch with nine workspaces: 1.63 cores for one
    /// second, 1.06 cores averaged over the worst five. A runaway loop instead
    /// pins a core indefinitely, so the gate trades a tighter burst window for a
    /// longer sustain window.
    static let `default` = WatchdogThresholds(
        memoryLimitBytes: 3 * 1024 * 1024 * 1024,
        cpuCoreFraction: 1.5,
        cpuSustainSeconds: 30
    )
}

nonisolated enum WatchdogBreach: Sendable, Equatable {
    case memory(bytes: UInt64, limit: UInt64)
    case cpu(fraction: Double, sustainedSeconds: Double)
}

/// Pure decision logic for the resource watchdog.
///
/// Feed it samples with a monotonic timestamp; it returns a breach when the process
/// crosses a threshold. Memory fires immediately; CPU must stay high for the sustain window.
nonisolated struct WatchdogEvaluator: Sendable {
    let thresholds: WatchdogThresholds

    private var previous: (cpuTimeSeconds: Double, at: TimeInterval)?
    private var cpuBreachStart: TimeInterval?

    init(thresholds: WatchdogThresholds = .default) {
        self.thresholds = thresholds
    }

    mutating func evaluate(_ sample: ProcessSample, at now: TimeInterval) -> WatchdogBreach? {
        if sample.memoryBytes >= thresholds.memoryLimitBytes {
            return .memory(bytes: sample.memoryBytes, limit: thresholds.memoryLimitBytes)
        }

        defer { previous = (sample.cpuTimeSeconds, now) }
        guard let previous else { return nil }

        let wall = now - previous.at
        guard wall > 0 else { return nil }

        let fraction = (sample.cpuTimeSeconds - previous.cpuTimeSeconds) / wall
        guard fraction >= thresholds.cpuCoreFraction else {
            cpuBreachStart = nil
            return nil
        }

        let start = cpuBreachStart ?? previous.at
        cpuBreachStart = start
        let sustained = now - start
        guard sustained >= thresholds.cpuSustainSeconds else { return nil }
        return .cpu(fraction: fraction, sustainedSeconds: sustained)
    }
}
