import Darwin
import Foundation

/// One reading of this process's resource usage.
nonisolated struct ProcessSample: Sendable, Equatable {
    /// Cumulative CPU time (user + system) across all threads, in seconds.
    let cpuTimeSeconds: Double
    /// Physical memory footprint in bytes, matching Activity Monitor's "Memory" column.
    let memoryBytes: UInt64
}

nonisolated protocol ProcessMetricsSampling: Sendable {
    func sample() -> ProcessSample
}

/// Reads live CPU and memory usage for the current process via Mach / libproc.
nonisolated struct ProcessMetrics: ProcessMetricsSampling {
    func sample() -> ProcessSample {
        ProcessSample(cpuTimeSeconds: Self.cpuTimeSeconds(), memoryBytes: Self.memoryFootprint())
    }

    private static func memoryFootprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.phys_footprint) : 0
    }

    /// `ri_user_time` and `ri_system_time` count mach absolute time units, not
    /// nanoseconds. On Apple Silicon one tick is 41.667 ns (`hw.tbfrequency` is
    /// 24 MHz), so reading them as nanoseconds under-reports CPU by about 42x.
    /// The timebase is 1/1 on Intel, where the same conversion is a no-op.
    static func seconds(machTicks: UInt64) -> Double {
        Double(machTicks) * timebaseNumerator / timebaseDenominator / 1_000_000_000
    }

    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        guard mach_timebase_info(&info) == KERN_SUCCESS, info.denom != 0 else {
            return mach_timebase_info_data_t(numer: 1, denom: 1)
        }
        return info
    }()

    private static let timebaseNumerator = Double(timebase.numer)
    private static let timebaseDenominator = Double(timebase.denom)

    private static func cpuTimeSeconds() -> Double {
        var usage = rusage_info_current()
        let result = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                proc_pid_rusage(getpid(), RUSAGE_INFO_CURRENT, rebound)
            }
        }
        guard result == 0 else { return 0 }
        return seconds(machTicks: usage.ri_user_time + usage.ri_system_time)
    }
}
