import Darwin
import Foundation
import Testing
@testable import Atelier

@Suite("Process metrics")
struct ProcessMetricsTests {
    private var timebase: mach_timebase_info_data_t {
        var info = mach_timebase_info_data_t()
        guard mach_timebase_info(&info) == KERN_SUCCESS, info.denom != 0 else {
            return mach_timebase_info_data_t(numer: 1, denom: 1)
        }
        return info
    }

    @Test("Mach ticks convert through the host timebase, not a raw nanosecond assumption")
    func conversionMatchesTimebase() {
        let ticks: UInt64 = 1_000_000_000
        let expected = Double(ticks) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
        #expect(ProcessMetrics.seconds(machTicks: ticks) == expected)
    }

    @Test("One second of CPU time reads back as one second")
    func oneSecondRoundTrip() {
        let ticksPerSecond = 1_000_000_000 * Double(timebase.denom) / Double(timebase.numer)
        let seconds = ProcessMetrics.seconds(machTicks: UInt64(ticksPerSecond.rounded()))
        #expect(abs(seconds - 1) < 0.000_001)
    }

    @Test("Conversion is linear and starts at zero")
    func linearAndZeroed() {
        #expect(ProcessMetrics.seconds(machTicks: 0) == 0)
        let single = ProcessMetrics.seconds(machTicks: 1_000_000)
        let double = ProcessMetrics.seconds(machTicks: 2_000_000)
        #expect(abs(double - 2 * single) < 1e-12)
    }

    @Test("Live CPU time advances and stays inside the wall-clock ceiling")
    func liveSampleStaysPlausible() {
        let cores = Double(ProcessInfo.processInfo.activeProcessorCount)
        let start = ProcessMetrics().sample()
        let startedAt = ContinuousClock.now
        var sink = 0.0
        for index in 1...4_000_000 { sink += Double(index).squareRoot() }
        #expect(sink > 0)
        let end = ProcessMetrics().sample()
        let wall = ContinuousClock.now - startedAt
        let wallSeconds = Double(wall.components.seconds)
            + Double(wall.components.attoseconds) / 1e18

        let used = end.cpuTimeSeconds - start.cpuTimeSeconds
        #expect(used > 0, "a busy loop must show CPU time")
        // The old nanosecond assumption reported about 1/42 of the real value,
        // which lands far below this floor on Apple Silicon.
        #expect(used > wallSeconds * 0.1, "CPU time must be on the same scale as wall time")
        #expect(used <= wallSeconds * cores + 0.1, "CPU time cannot exceed every core")
    }
}
