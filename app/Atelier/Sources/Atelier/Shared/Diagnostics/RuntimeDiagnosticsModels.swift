import Foundation

nonisolated protocol RuntimeMonotonicClock: Sendable {
    func now() -> Double
}

nonisolated struct SystemRuntimeMonotonicClock: RuntimeMonotonicClock {
    func now() -> Double {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
    }
}

nonisolated enum RuntimeScalar: Codable, Sendable, Equatable {
    case string(String)
    case integer(Int)
    case double(Double)
    case boolean(Bool)

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let decoded = try? value.decode(Bool.self) {
            self = .boolean(decoded)
        } else if let decoded = try? value.decode(Int.self) {
            self = .integer(decoded)
        } else if let decoded = try? value.decode(Double.self) {
            self = .double(decoded)
        } else {
            self = .string(try value.decode(String.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .string(let item): try value.encode(item)
        case .integer(let item): try value.encode(item)
        case .double(let item): try value.encode(item)
        case .boolean(let item): try value.encode(item)
        }
    }

    static func == (lhs: RuntimeScalar, rhs: RuntimeScalar) -> Bool {
        switch (lhs, rhs) {
        case (.string(let left), .string(let right)): left == right
        case (.integer(let left), .integer(let right)): left == right
        case (.double(let left), .double(let right)): left == right
        case (.integer(let left), .double(let right)): Double(left) == right
        case (.double(let left), .integer(let right)): left == Double(right)
        case (.boolean(let left), .boolean(let right)): left == right
        default: false
        }
    }
}

nonisolated struct RuntimeEvent: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let monotonicTimeSeconds: Double
    let category: String
    let name: String
    let durationMs: Double?
    let metadata: [String: RuntimeScalar]
    let correlationID: String?

    init(
        id: UUID = UUID(),
        monotonicTimeSeconds: Double,
        category: String,
        name: String,
        durationMs: Double? = nil,
        metadata: [String: RuntimeScalar] = [:],
        correlationID: String? = nil
    ) {
        self.id = id
        self.monotonicTimeSeconds = monotonicTimeSeconds
        self.category = category
        self.name = name
        self.durationMs = durationMs
        self.metadata = metadata
        self.correlationID = correlationID
    }
}

nonisolated struct RuntimeRingBuffer<Element: Sendable>: Sendable {
    private(set) var elements: [Element] = []
    private(set) var droppedCount = 0
    let capacity: Int

    init(capacity: Int) {
        self.capacity = max(1, capacity)
        elements.reserveCapacity(self.capacity)
    }

    mutating func append(_ element: Element) {
        if elements.count == capacity {
            elements.removeFirst()
            droppedCount += 1
        }
        elements.append(element)
    }
}

nonisolated struct RuntimeProcessSnapshot: Codable, Sendable, Equatable {
    var pid: Int32 = getpid()
    var uptimeSeconds = 0.0
    var cpuPercent = 0.0
    var cpuTimeSeconds = 0.0
    var physicalFootprintBytes: UInt64 = 0
}

nonisolated struct RuntimeMainThreadSnapshot: Codable, Sendable, Equatable {
    var lastHeartbeatAt = 0.0
    var heartbeatAgeMs = 0.0
    var pendingHeartbeat = false
}

nonisolated struct RuntimeFileTabMetric: Codable, Sendable, Equatable {
    let relativePath: String
    let loadedBytes: Int
    let loadState: String
    let isPreview: Bool
}

nonisolated struct RuntimeWorkspaceSnapshot: Codable, Sendable, Equatable {
    var active = false
    var relativeRootName: String?
    var tabCount = 0
    var fileTabCount = 0
    var terminalTabCount = 0
    var gitDiffTabCount = 0
    var gemmaTabCount = 0
    var selectedTabKind: String?
    var selectedFileRelativePath: String?
    var loadedFileBytes = 0
    var fileSessionCount = 0
    var previewFileCount = 0
    var permanentFileCount = 0
    var fileTabs: [RuntimeFileTabMetric] = []
}

nonisolated struct RuntimeEditorSnapshot: Codable, Sendable, Equatable {
    var selectedControllerID: String?
    var liveControllerCount = 0
    var expectedControllerCount = 0
    var contentBytes = 0
    var lineCount = 0
    var viewportOriginY = 0.0
    var viewportHeight = 0.0
    var documentHeight = 0.0
    var maximumScrollY = 0.0
    var canScrollVertically = false
    var scrollInputsWindow = 0
    var boundsChangesWindow = 0
    var eligibleNoMovementInputsWindow = 0
    var documentHeightChangesWindow = 0
    var highlightState = "idle"
    var highlightDurationMs = 0.0
    var highlightCancellationCount = 0
    var textApplyDurationMs = 0.0
    var attached = false
}

nonisolated struct RuntimeDiagnosticsSnapshot: Codable, Sendable, Equatable {
    var eventCount = 0
    var droppedEventCount = 0
    var lastFlushDurationMs = 0.0
    var lastWriteError: String?

    private enum CodingKeys: String, CodingKey {
        case eventCount
        case droppedEventCount
        case lastFlushDurationMs
        case lastWriteError
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(eventCount, forKey: .eventCount)
        try container.encode(droppedEventCount, forKey: .droppedEventCount)
        try container.encode(lastFlushDurationMs, forKey: .lastFlushDurationMs)
        if let lastWriteError {
            try container.encode(lastWriteError, forKey: .lastWriteError)
        } else {
            try container.encodeNil(forKey: .lastWriteError)
        }
    }
}

nonisolated struct RuntimeVerdict: Codable, Sendable, Equatable {
    let code: String
    let severity: String
    let confidence: String
    let summary: String
    let evidence: [String: RuntimeScalar]
}

nonisolated struct RuntimeSnapshot: Codable, Sendable, Equatable {
    let schemaVersion: Int
    let generatedAt: String
    let monotonicTimeSeconds: Double
    let process: RuntimeProcessSnapshot
    let mainThread: RuntimeMainThreadSnapshot
    let workspace: RuntimeWorkspaceSnapshot
    let editor: RuntimeEditorSnapshot
    let diagnostics: RuntimeDiagnosticsSnapshot
    let verdicts: [RuntimeVerdict]
}

nonisolated struct RuntimeFlightRecorderSnapshot: Codable, Sendable, Equatable {
    let schemaVersion: Int
    let generatedAt: String
    let events: [RuntimeEvent]
    let droppedEventCount: Int
}

nonisolated struct RuntimeMainSnapshot: Sendable, Equatable {
    var workspace = RuntimeWorkspaceSnapshot()
    var editor = RuntimeEditorSnapshot()
}

nonisolated struct RuntimeCPUDelta: Sendable {
    private var previousSample: ProcessSample?
    private var previousTime: Double?

    mutating func consume(_ sample: ProcessSample, at time: Double) -> Double {
        defer {
            previousSample = sample
            previousTime = time
        }
        guard let previousSample, let previousTime else { return 0 }
        let elapsed = time - previousTime
        guard elapsed > 0 else { return 0 }
        let cpuDelta = max(0, sample.cpuTimeSeconds - previousSample.cpuTimeSeconds)
        return cpuDelta / elapsed * 100
    }
}

nonisolated struct RuntimeHeartbeatState: Sendable, Equatable {
    private(set) var lastAcknowledgedAt: Double
    private(set) var pending = false

    init(startedAt: Double) {
        lastAcknowledgedAt = startedAt
    }

    mutating func request() -> Bool {
        guard !pending else { return false }
        pending = true
        return true
    }

    mutating func acknowledge(at time: Double) {
        lastAcknowledgedAt = time
        pending = false
    }

    func ageMilliseconds(at time: Double) -> Double {
        max(0, time - lastAcknowledgedAt) * 1_000
    }
}

nonisolated struct RuntimeVerdictPolicy: Sendable {
    let heartbeatStallMs: Double
    let cpuBoundPercent: Double
    let blockedPercent: Double
    let scrollInputMinimum: Int
    let heightChangeMinimum: Int
    let memoryPressureBytes: UInt64
    let layoutTolerance: Double

    static let `default` = RuntimeVerdictPolicy(
        heartbeatStallMs: 1_000,
        cpuBoundPercent: 75,
        blockedPercent: 25,
        scrollInputMinimum: 3,
        heightChangeMinimum: 3,
        memoryPressureBytes: 2_500_000_000,
        layoutTolerance: 1
    )

    func evaluate(
        process: RuntimeProcessSnapshot,
        mainThread: RuntimeMainThreadSnapshot,
        editor: RuntimeEditorSnapshot,
        controllerLeakAgeSeconds: Double?,
        writerError: String?
    ) -> [RuntimeVerdict] {
        var verdicts: [RuntimeVerdict] = []
        if mainThread.heartbeatAgeMs >= heartbeatStallMs {
            if process.cpuPercent >= cpuBoundPercent {
                verdicts.append(RuntimeVerdict(
                    code: "mainThreadCpuBoundSuspected",
                    severity: "warning",
                    confidence: "medium",
                    summary: "Main heartbeat is stale while process CPU is high.",
                    evidence: [
                        "heartbeatAgeMs": .double(mainThread.heartbeatAgeMs),
                        "cpuPercent": .double(process.cpuPercent)
                    ]
                ))
            } else if process.cpuPercent <= blockedPercent {
                verdicts.append(RuntimeVerdict(
                    code: "mainThreadBlockedSuspected",
                    severity: "warning",
                    confidence: "medium",
                    summary: "Main heartbeat is stale while process CPU is low.",
                    evidence: [
                        "heartbeatAgeMs": .double(mainThread.heartbeatAgeMs),
                        "cpuPercent": .double(process.cpuPercent)
                    ]
                ))
            }
        }
        let awayFromEdge = editor.viewportOriginY > layoutTolerance
            && editor.viewportOriginY < editor.maximumScrollY - layoutTolerance
        if editor.canScrollVertically,
           awayFromEdge,
           editor.scrollInputsWindow >= scrollInputMinimum,
           editor.eligibleNoMovementInputsWindow >= scrollInputMinimum,
           editor.boundsChangesWindow == 0 {
            verdicts.append(RuntimeVerdict(
                code: "scrollInputWithoutMovement",
                severity: "warning",
                confidence: "high",
                summary: "Eligible scroll inputs did not move the editor viewport.",
                evidence: [
                    "eligibleInputs": .integer(editor.eligibleNoMovementInputsWindow),
                    "boundsChanges": .integer(editor.boundsChangesWindow),
                    "maximumScrollY": .double(editor.maximumScrollY)
                ]
            ))
        }
        if editor.documentHeightChangesWindow >= heightChangeMinimum {
            verdicts.append(RuntimeVerdict(
                code: "documentHeightChurn",
                severity: "warning",
                confidence: "high",
                summary: "Editor document height changed repeatedly without a known layout input.",
                evidence: [
                    "heightChanges": .integer(editor.documentHeightChangesWindow),
                    "documentHeight": .double(editor.documentHeight)
                ]
            ))
        }
        if let controllerLeakAgeSeconds, controllerLeakAgeSeconds >= 2 {
            verdicts.append(RuntimeVerdict(
                code: "editorControllerLeakSuspected",
                severity: "warning",
                confidence: "medium",
                summary: "Live editor controllers exceed open file tabs after the grace window.",
                evidence: [
                    "liveControllers": .integer(editor.liveControllerCount),
                    "expectedControllers": .integer(editor.expectedControllerCount),
                    "graceSeconds": .double(controllerLeakAgeSeconds)
                ]
            ))
        }
        if process.physicalFootprintBytes >= memoryPressureBytes {
            verdicts.append(RuntimeVerdict(
                code: "physicalFootprintPressure",
                severity: "warning",
                confidence: "high",
                summary: "Physical footprint is near the watchdog memory limit.",
                evidence: [
                    "physicalFootprintBytes": .double(Double(process.physicalFootprintBytes))
                ]
            ))
        }
        if let writerError {
            verdicts.append(RuntimeVerdict(
                code: "diagnosticsWriterFailure",
                severity: "error",
                confidence: "high",
                summary: "Runtime diagnostics could not write its latest snapshot.",
                evidence: ["error": .string(writerError)]
            ))
        }
        return verdicts
    }
}

nonisolated enum RuntimeAtomicWriter {
    static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let manager = FileManager.default
        let directory = url.deletingLastPathComponent()
        try manager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let data = try JSONEncoder.runtimeDiagnostics.encode(value)
        try data.write(to: url, options: [.atomic])
        try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

nonisolated extension JSONEncoder {
    static var runtimeDiagnostics: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

nonisolated enum RuntimeProbeCommand: String, Codable, Sendable {
    case main
    case editor
    case editorScroll = "editor-scroll"
}

nonisolated struct RuntimeProbeRequest: Codable, Sendable, Equatable {
    let schemaVersion: Int
    let id: UUID
    let command: RuntimeProbeCommand
    let arguments: [String: RuntimeScalar]
    let requestedAt: String
}

nonisolated struct RuntimeProbeResponse: Codable, Sendable, Equatable {
    let schemaVersion: Int
    let id: UUID
    let command: RuntimeProbeCommand
    let status: String
    let completedAt: String
    let elapsedMs: Double
    let result: [String: RuntimeScalar]
    let editor: RuntimeEditorSnapshot?
    let error: String?
}

@MainActor
protocol RuntimeDiagnosableEditorSurface: EditorSurface {
    var runtimeDiagnosticID: String { get }
    func runtimeSnapshot() -> RuntimeEditorSnapshot
    func runScrollProbe(delta: Double, restore: Bool) async -> (
        status: String,
        elapsedMs: Double,
        result: [String: RuntimeScalar]
    )
}
