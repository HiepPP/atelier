import Foundation

/// Persisted record of why the watchdog force-exited, read on the next launch.
nonisolated struct ResourceExitRecord: Codable, Sendable, Equatable {
    enum Reason: String, Codable, Sendable {
        case cpu
        case memory
    }

    let reason: Reason
    let detail: String
    let occurredAt: Date

    init(breach: WatchdogBreach, occurredAt: Date) {
        switch breach {
        case let .memory(bytes, limit):
            reason = .memory
            detail = "Memory reached \(Self.gigabytes(bytes)) (limit \(Self.gigabytes(limit)))."
        case let .cpu(fraction, sustainedSeconds):
            reason = .cpu
            let percent = Int((fraction * 100).rounded())
            let seconds = Int(sustainedSeconds.rounded())
            detail = "CPU stayed at \(percent)% for \(seconds)s."
        }
        self.occurredAt = occurredAt
    }

    private static func gigabytes(_ bytes: UInt64) -> String {
        let value = Double(bytes) / (1024 * 1024 * 1024)
        return String(format: "%.2f GB", value)
    }
}

/// Reads and writes the watchdog exit marker in Application Support.
nonisolated enum ResourceExitMarker {
    static func defaultURL(fileManager: FileManager = .default) -> URL? {
        guard let base = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else {
            return nil
        }
        let directory = base.appendingPathComponent("Atelier", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("last-exit.json")
    }

    static func write(_ record: ResourceExitRecord, to url: URL) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func read(from url: URL) -> ResourceExitRecord? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ResourceExitRecord.self, from: data)
    }

    static func clear(at url: URL, fileManager: FileManager = .default) {
        try? fileManager.removeItem(at: url)
    }
}
