import Foundation
import Testing
@testable import Atelier

@Suite("Resource watchdog")
struct ResourceWatchdogTests {
    private static let limit: UInt64 = 3 * 1024 * 1024 * 1024
    private static let thresholds = WatchdogThresholds(
        memoryLimitBytes: limit,
        cpuCoreFraction: 1.0,
        cpuSustainSeconds: 5
    )

    @Test("Memory over the limit fires immediately")
    func memoryInstantBreach() {
        var evaluator = WatchdogEvaluator(thresholds: Self.thresholds)
        let breach = evaluator.evaluate(
            ProcessSample(cpuTimeSeconds: 0, memoryBytes: Self.limit),
            at: 0
        )
        #expect(breach == .memory(bytes: Self.limit, limit: Self.limit))
    }

    @Test("Memory just under the limit does not fire")
    func memoryUnderLimit() {
        var evaluator = WatchdogEvaluator(thresholds: Self.thresholds)
        let breach = evaluator.evaluate(
            ProcessSample(cpuTimeSeconds: 0, memoryBytes: Self.limit - 1),
            at: 0
        )
        #expect(breach == nil)
    }

    @Test("Sustained 100% CPU fires only after the sustain window")
    func cpuSustainedBreach() {
        var evaluator = WatchdogEvaluator(thresholds: Self.thresholds)
        // One core fully busy: cpu time advances 1s per 1s of wall time.
        var breach: WatchdogBreach?
        for second in 0...5 {
            breach = evaluator.evaluate(
                ProcessSample(cpuTimeSeconds: Double(second), memoryBytes: 0),
                at: TimeInterval(second)
            )
            if second < 5 {
                #expect(breach == nil, "should not fire before 5s (second=\(second))")
            }
        }
        #expect(breach == .cpu(fraction: 1.0, sustainedSeconds: 5))
    }

    @Test("A CPU spike that recovers resets the sustain counter")
    func cpuSpikeResets() {
        var evaluator = WatchdogEvaluator(thresholds: Self.thresholds)
        // 3s of full load, then idle, then load again - never 5s continuous.
        let cpuTimes: [Double] = [0, 1, 2, 3, 3, 3, 4, 5, 6]
        var breach: WatchdogBreach?
        for (index, cpu) in cpuTimes.enumerated() {
            breach = evaluator.evaluate(
                ProcessSample(cpuTimeSeconds: cpu, memoryBytes: 0),
                at: TimeInterval(index)
            )
            #expect(breach == nil, "no continuous 5s window (index=\(index))")
        }
    }

    @Test("Half-core load never fires")
    func cpuBelowFraction() {
        var evaluator = WatchdogEvaluator(thresholds: Self.thresholds)
        var breach: WatchdogBreach?
        for second in 0...20 {
            breach = evaluator.evaluate(
                ProcessSample(cpuTimeSeconds: Double(second) * 0.5, memoryBytes: 0),
                at: TimeInterval(second)
            )
            #expect(breach == nil)
        }
    }

    @Test("Default thresholds keep the CPU gate above measured launch load")
    func defaultThresholdsClearLaunchLoad() {
        #expect(WatchdogThresholds.default.cpuCoreFraction == 1.5)
        #expect(WatchdogThresholds.default.cpuSustainSeconds == 30)

        // Measured launch shape with nine workspaces: a 1.63-core second, a few
        // seconds near one core, then idle.
        let perSecondCores: [Double] = [1.63, 1.21, 1.06, 0.98, 0.74, 0.31, 0.05, 0.02, 0.01, 0.01]
        var evaluator = WatchdogEvaluator(thresholds: .default)
        var cpuTime = 0.0
        for (index, cores) in perSecondCores.enumerated() {
            let breach = evaluator.evaluate(
                ProcessSample(cpuTimeSeconds: cpuTime, memoryBytes: 0),
                at: TimeInterval(index)
            )
            #expect(breach == nil, "launch load must not force-exit (second=\(index))")
            cpuTime += cores
        }
    }

    @Test("A runaway loop still trips the default gate")
    func runawayLoopBreachesDefaults() {
        var evaluator = WatchdogEvaluator(thresholds: .default)
        var breach: WatchdogBreach?
        for second in 0...30 {
            breach = evaluator.evaluate(
                ProcessSample(cpuTimeSeconds: Double(second) * 2, memoryBytes: 0),
                at: TimeInterval(second)
            )
            if second < 30 {
                #expect(breach == nil, "must wait out the sustain window (second=\(second))")
            }
        }
        #expect(breach == .cpu(fraction: 2, sustainedSeconds: 30))
    }

    @Test("Exit marker round-trips through disk")
    func markerRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("atelier-watchdog-\(UUID().uuidString).json")
        let record = ResourceExitRecord(
            breach: .memory(bytes: Self.limit, limit: Self.limit),
            occurredAt: Date(timeIntervalSince1970: 1000)
        )
        ResourceExitMarker.write(record, to: url)
        #expect(ResourceExitMarker.read(from: url) == record)
        ResourceExitMarker.clear(at: url)
        #expect(ResourceExitMarker.read(from: url) == nil)
    }

    @Test("Live process metrics return sane, non-zero values")
    func liveMetricsAreSane() {
        let sample = ProcessMetrics().sample()
        #expect(sample.memoryBytes > 0, "phys_footprint syscall should report memory")
        #expect(sample.cpuTimeSeconds >= 0, "rusage syscall should report CPU time")
    }

    @Test("shouldRun is off under selftest and the disable env var")
    func gateRespectsOverrides() {
        let defaults = UserDefaults(suiteName: "watchdog-test-\(UUID().uuidString)")!
        #expect(ResourceWatchdog.shouldRun(arguments: ["Atelier"], environment: [:], defaults: defaults))
        #expect(!ResourceWatchdog.shouldRun(arguments: ["Atelier", "--selftest"], environment: [:], defaults: defaults))
        #expect(!ResourceWatchdog.shouldRun(
            arguments: ["Atelier"],
            environment: ["ATELIER_DISABLE_WATCHDOG": "1"],
            defaults: defaults
        ))
        defaults.set(false, forKey: ResourceWatchdog.settingsKey)
        #expect(!ResourceWatchdog.shouldRun(arguments: ["Atelier"], environment: [:], defaults: defaults))
    }
}
