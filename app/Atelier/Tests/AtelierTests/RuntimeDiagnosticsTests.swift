import Foundation
import Testing
@testable import Atelier

@Suite("Runtime diagnostics")
struct RuntimeDiagnosticsTests {
    @Test("Flight recorder preserves order and caps at 512")
    func ringBufferCapAndOrdering() {
        var buffer = RuntimeRingBuffer<Int>(capacity: 512)
        for value in 0..<600 { buffer.append(value) }
        #expect(buffer.elements.count == 512)
        #expect(buffer.elements.first == 88)
        #expect(buffer.elements.last == 599)
        #expect(buffer.droppedCount == 88)
    }

    @Test("Snapshot schema round-trips without private content")
    func schemaAndPrivacy() throws {
        let snapshot = RuntimeSnapshot(
            schemaVersion: 1,
            generatedAt: "2026-07-21T00:00:00Z",
            monotonicTimeSeconds: 10,
            process: RuntimeProcessSnapshot(),
            mainThread: RuntimeMainThreadSnapshot(),
            workspace: RuntimeWorkspaceSnapshot(
                active: true,
                relativeRootName: "atelier",
                selectedFileRelativePath: "Sources/File.swift"
            ),
            editor: RuntimeEditorSnapshot(contentBytes: 42, lineCount: 2),
            diagnostics: RuntimeDiagnosticsSnapshot(),
            verdicts: []
        )
        let data = try JSONEncoder.runtimeDiagnostics.encode(snapshot)
        let encoded = try #require(String(data: data, encoding: .utf8))
        #expect(!encoded.contains("SECRET_FILE_CONTENT"))
        #expect(!encoded.contains("/Users/"))
        #expect(encoded.contains("\"lastWriteError\" : null"))
        #expect(try JSONDecoder().decode(RuntimeSnapshot.self, from: data) == snapshot)
    }

    @Test("Atomic writer replaces generated JSON")
    func atomicWriter() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("atelier-runtime-writer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("snapshot.json")
        try RuntimeAtomicWriter.write(["value": 1], to: url)
        try RuntimeAtomicWriter.write(["value": 2], to: url)
        let decoded = try JSONDecoder().decode([String: Int].self, from: Data(contentsOf: url))
        #expect(decoded == ["value": 2])
    }

    @Test("Heartbeat fake clock detects lag and blocks backlog")
    func heartbeatLagAndSingleOutstandingRequest() {
        let clock = FakeRuntimeClock(now: 10)
        var heartbeat = RuntimeHeartbeatState(startedAt: clock.now())
        let firstRequest = heartbeat.request()
        let duplicateRequest = heartbeat.request()
        #expect(firstRequest)
        #expect(!duplicateRequest)
        clock.value = 11.25
        #expect(heartbeat.ageMilliseconds(at: clock.now()) == 1_250)
        heartbeat.acknowledge(at: clock.now())
        let requestAfterAck = heartbeat.request()
        #expect(requestAfterAck)
    }

    @Test("CPU delta uses monotonic elapsed time")
    func cpuDeltaCalculation() {
        var delta = RuntimeCPUDelta()
        #expect(delta.consume(ProcessSample(cpuTimeSeconds: 1, memoryBytes: 0), at: 10) == 0)
        #expect(delta.consume(ProcessSample(cpuTimeSeconds: 2.5, memoryBytes: 0), at: 12) == 75)
    }

    @Test("Verdicts enforce heartbeat and scroll thresholds")
    func verdictThresholdsAndScrollFiltering() {
        let policy = RuntimeVerdictPolicy.default
        let process = RuntimeProcessSnapshot(cpuPercent: 90)
        let main = RuntimeMainThreadSnapshot(heartbeatAgeMs: 1_100, pendingHeartbeat: true)
        var editor = RuntimeEditorSnapshot(
            viewportOriginY: 100,
            maximumScrollY: 1_000,
            canScrollVertically: true,
            scrollInputsWindow: 3,
            boundsChangesWindow: 0,
            eligibleNoMovementInputsWindow: 3
        )
        var verdicts = policy.evaluate(
            process: process,
            mainThread: main,
            editor: editor,
            controllerLeakAgeSeconds: nil,
            writerError: nil
        )
        #expect(verdicts.contains { $0.code == "mainThreadCpuBoundSuspected" })
        #expect(verdicts.contains { $0.code == "scrollInputWithoutMovement" })

        editor.viewportOriginY = 0
        verdicts = policy.evaluate(
            process: process,
            mainThread: main,
            editor: editor,
            controllerLeakAgeSeconds: nil,
            writerError: nil
        )
        #expect(!verdicts.contains { $0.code == "scrollInputWithoutMovement" })
    }

    @Test("Height churn and controller leak require thresholds")
    func churnAndControllerGrace() {
        let policy = RuntimeVerdictPolicy.default
        var editor = RuntimeEditorSnapshot(documentHeightChangesWindow: 2)
        var verdicts = policy.evaluate(
            process: RuntimeProcessSnapshot(),
            mainThread: RuntimeMainThreadSnapshot(),
            editor: editor,
            controllerLeakAgeSeconds: 1.99,
            writerError: nil
        )
        #expect(!verdicts.contains { $0.code == "documentHeightChurn" })
        #expect(!verdicts.contains { $0.code == "editorControllerLeakSuspected" })

        editor.documentHeightChangesWindow = 3
        editor.liveControllerCount = 2
        editor.expectedControllerCount = 1
        verdicts = policy.evaluate(
            process: RuntimeProcessSnapshot(),
            mainThread: RuntimeMainThreadSnapshot(),
            editor: editor,
            controllerLeakAgeSeconds: 2,
            writerError: nil
        )
        #expect(verdicts.contains { $0.code == "documentHeightChurn" })
        #expect(verdicts.contains { $0.code == "editorControllerLeakSuspected" })
    }

    @Test("Probe request and response encode with stable schema")
    func probeEncoding() throws {
        let request = RuntimeProbeRequest(
            schemaVersion: 1,
            id: UUID(),
            command: .editorScroll,
            arguments: ["delta": .double(400), "restore": .boolean(true)],
            requestedAt: "2026-07-21T00:00:00Z"
        )
        let requestData = try JSONEncoder.runtimeDiagnostics.encode(request)
        #expect(try JSONDecoder().decode(RuntimeProbeRequest.self, from: requestData) == request)

        let response = RuntimeProbeResponse(
            schemaVersion: 1,
            id: request.id,
            command: request.command,
            status: "timeout",
            completedAt: "2026-07-21T00:00:02Z",
            elapsedMs: 2_000,
            result: [:],
            editor: nil,
            error: "timeout"
        )
        let responseData = try JSONEncoder.runtimeDiagnostics.encode(response)
        #expect(try JSONDecoder().decode(RuntimeProbeResponse.self, from: responseData) == response)
    }

    @Test("Diagnostics gate disables selftest and environment override")
    func disabledMode() {
        #expect(!RuntimeDiagnosticsService.shouldRun(arguments: ["Atelier", "--selftest"], environment: [:]))
        #expect(!RuntimeDiagnosticsService.shouldRun(
            arguments: ["Atelier"],
            environment: ["ATELIER_DISABLE_RUNTIME_DIAGNOSTICS": "1"]
        ))
        #expect(RuntimeDiagnosticsService.shouldRun(arguments: ["Atelier"], environment: [:]))
    }
}

nonisolated private final class FakeRuntimeClock: RuntimeMonotonicClock, @unchecked Sendable {
    var value: Double

    init(now: Double) {
        value = now
    }

    func now() -> Double { value }
}
