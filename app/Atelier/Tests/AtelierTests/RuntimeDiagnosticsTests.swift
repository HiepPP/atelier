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

    @Test("Ring buffer sequence marks appends so an idle flush can skip writing")
    func ringBufferSequenceTracksAppends() {
        var buffer = RuntimeRingBuffer<Int>(capacity: 4)
        #expect(buffer.sequence == 0)
        buffer.append(1)
        let afterFirst = buffer.sequence
        #expect(afterFirst == 1)
        for value in 2...6 { buffer.append(value) }
        // Evictions still count as changes: the encoded window moved.
        #expect(buffer.sequence == 6)
        #expect(buffer.droppedCount == 2)
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
            git: GitCommandQueueSnapshot(
                activeCount: 2,
                queuedCount: 3,
                concurrencyLimit: 4,
                queueCapacity: 64,
                oldestActiveAgeMs: 250
            ),
            fileTree: RuntimeFileTreeSnapshot(
                relativeRootName: "atelier",
                rootLoadState: "loaded",
                rootEntryCount: 12
            ),
            terminal: RuntimeTerminalSnapshot(
                controllerCount: 1,
                activeControllerCount: 1,
                attachedControllerCount: 1,
                firstResponderKind: "terminal"
            ),
            diagnostics: RuntimeDiagnosticsSnapshot(),
            verdicts: []
        )
        let data = try JSONEncoder.runtimeDiagnostics.encode(snapshot)
        let encoded = try #require(String(data: data, encoding: .utf8))
        #expect(!encoded.contains("SECRET_FILE_CONTENT"))
        #expect(!encoded.contains("/Users/"))
        // The key stays explicit rather than omitted; formatting is not part of
        // the contract, so assert on structure instead of whitespace.
        #expect(encoded.contains("\"lastWriteError\""))
        #expect(!encoded.contains("\n"))
        let reencoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let diagnostics = reencoded?["diagnostics"] as? [String: Any]
        #expect(diagnostics?["lastWriteError"] is NSNull)
        #expect(try JSONDecoder().decode(RuntimeSnapshot.self, from: data) == snapshot)
    }

    @Test("Git command metrics enforce capacity and active age")
    func gitCommandMetricsAreBounded() {
        var state = GitCommandExecutionState(capacity: 2, concurrencyLimit: 1)
        let first = UUID()
        let second = UUID()
        let firstEnqueued = state.enqueue(first)
        let secondEnqueued = state.enqueue(second)
        let overflowEnqueued = state.enqueue(UUID())
        let firstBegan = state.begin(first, at: 10)
        #expect(firstEnqueued)
        #expect(secondEnqueued)
        #expect(!overflowEnqueued)
        #expect(firstBegan)
        let snapshot = state.snapshot(at: 10.25)
        #expect(snapshot.activeCount == 1)
        #expect(snapshot.queuedCount == 1)
        #expect(snapshot.oldestActiveAgeMs == 250)
        state.remove(first)
        #expect(state.snapshot(at: 11).activeCount == 0)
    }

    @Test("File tree root metrics are bounded and path-private")
    func fileTreeRootMetricsAreBounded() {
        let clock = FakeRuntimeClock(now: 10)
        let store = RuntimeFileTreeMetricsStore(clock: clock)
        for index in 0...RuntimeFileTreeMetricsStore.capacity {
            store.register(rootPath: "/private/workspace/\(index)", relativeRootName: "root-\(index)")
        }
        store.loading(rootPath: "/private/workspace/0")
        clock.value = 10.5
        var snapshot = store.snapshot(rootPath: "/private/workspace/0")
        #expect(snapshot.rootLoadState == "loading")
        #expect(snapshot.rootLoadAgeMs == 500)
        #expect(snapshot.relativeRootName == "root-0")
        store.loaded(rootPath: "/private/workspace/0", entryCount: 42)
        snapshot = store.snapshot(rootPath: "/private/workspace/0")
        #expect(snapshot.rootLoadState == "loaded")
        #expect(snapshot.rootEntryCount == 42)
        #expect(store.snapshot(rootPath: "/private/workspace/64").rootLoadState == "unavailable")
    }

    @Test("Hidden workspace terminals never become active")
    func hiddenWorkspaceTerminalActivation() {
        let tabID = UUID()
        #expect(TerminalWorkspaceActivationPolicy.isActive(
            workspaceIsActive: true,
            selectedID: tabID,
            tabID: tabID
        ))
        #expect(!TerminalWorkspaceActivationPolicy.isActive(
            workspaceIsActive: false,
            selectedID: tabID,
            tabID: tabID
        ))
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
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions]
        #expect(mode as? Int == 0o600)
    }

    @Test("Prepared runtime directory is created once with owner-only access")
    func preparedDirectoryPermissions() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("atelier-runtime-prepare-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("current/snapshot.json")
        try RuntimeAtomicWriter.prepareDirectory(for: url)
        let parent = url.deletingLastPathComponent().path
        #expect(FileManager.default.fileExists(atPath: parent))
        let mode = try FileManager.default.attributesOfItem(atPath: parent)[.posixPermissions]
        #expect(mode as? Int == 0o700)
        // Idempotent: a second call must not throw on an existing directory.
        try RuntimeAtomicWriter.prepareDirectory(for: url)
        try RuntimeAtomicWriter.write(["value": 1], to: url)
        #expect(FileManager.default.fileExists(atPath: url.path))
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

    @Test("Heartbeat cadence halves idle pings and pauses when hidden")
    func heartbeatCadence() {
        let interval = RuntimeHeartbeatCadencePolicy.interval
        #expect(interval == 0.5)
        // Visible and past the interval: ping.
        #expect(RuntimeHeartbeatCadencePolicy.shouldRequest(
            isApplicationVisible: true,
            needsSnapshotCapture: false,
            sinceLastRequest: interval
        ))
        // Visible but inside the interval: skip, so a 250ms tick pings 2/s.
        #expect(!RuntimeHeartbeatCadencePolicy.shouldRequest(
            isApplicationVisible: true,
            needsSnapshotCapture: false,
            sinceLastRequest: 0.25
        ))
        // A pending snapshot capture still forces a ping so published state
        // stays as fresh as the flush.
        #expect(RuntimeHeartbeatCadencePolicy.shouldRequest(
            isApplicationVisible: true,
            needsSnapshotCapture: true,
            sinceLastRequest: 0
        ))
        // Hidden: never ping, not even for a capture.
        #expect(!RuntimeHeartbeatCadencePolicy.shouldRequest(
            isApplicationVisible: false,
            needsSnapshotCapture: true,
            sinceLastRequest: 60
        ))
    }

    @Test("A paused heartbeat raises no main-thread verdict")
    func pausedHeartbeatSuppressesVerdicts() {
        let policy = RuntimeVerdictPolicy.default
        let stale = RuntimeMainThreadSnapshot(heartbeatAgeMs: 60_000, pendingHeartbeat: false)
        var paused = stale
        paused.heartbeatPaused = true

        let liveVerdicts = policy.evaluate(
            process: RuntimeProcessSnapshot(cpuPercent: 5),
            mainThread: stale,
            editor: RuntimeEditorSnapshot(),
            controllerLeakAgeSeconds: nil,
            writerError: nil
        )
        let pausedVerdicts = policy.evaluate(
            process: RuntimeProcessSnapshot(cpuPercent: 5),
            mainThread: paused,
            editor: RuntimeEditorSnapshot(),
            controllerLeakAgeSeconds: nil,
            writerError: nil
        )

        #expect(liveVerdicts.contains { $0.code == "mainThreadBlockedSuspected" })
        #expect(pausedVerdicts.isEmpty)
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

    @Test("Diff probe reports footer numbers without diff content")
    @MainActor
    func diffProbeMetrics() throws {
        #expect(RuntimeProbeCommand(rawValue: "diff") == .diff)

        let none = AppModel.diffProbeMetrics(nil)
        #expect(none["diffState"] == .string("noSelectedDiff"))
        #expect(none["lineCount"] == nil)

        let change = GitChange(
            path: "src/big.txt",
            originalPath: nil,
            kind: .untracked,
            isStaged: false,
            isUnstaged: true
        )
        // A workspace path that is not a repository leaves the session in a
        // terminal non-loaded state, which the probe must still describe.
        let session = GitDiffSession(
            selection: DiffSelection(change: change, staged: false),
            workspacePath: FileManager.default.temporaryDirectory.path
        )
        defer { session.close() }
        let pending = AppModel.diffProbeMetrics(session)
        #expect(pending["diffPath"] == .string("src/big.txt"))
        #expect(pending["diffStaged"] == .boolean(false))
        #expect(pending["showsFullDiff"] == .boolean(false))
        // Never report diff text, only counts and identifiers.
        let encoded = try JSONEncoder.runtimeDiagnostics.encode(pending)
        let text = try #require(String(data: encoded, encoding: .utf8))
        #expect(!text.contains("line "))
        #expect(!text.contains("@@"))
    }

    @Test("Diff probe response round-trips with the loaded document counts")
    func diffProbeResponseEncoding() throws {
        let response = RuntimeProbeResponse(
            schemaVersion: 1,
            id: UUID(),
            command: .diff,
            status: "ok",
            completedAt: "2026-07-30T00:00:00Z",
            elapsedMs: 1,
            result: [
                "selectedTabKind": .string("gitDiff"),
                "gitDiffTabCount": .integer(1),
                "diffState": .string("loaded"),
                "lineCount": .integer(20_000),
                "hiddenLineCount": .integer(501),
                "additions": .integer(20_500),
                "showsTruncationFooter": .boolean(true)
            ],
            editor: nil,
            error: nil
        )
        let data = try JSONEncoder.runtimeDiagnostics.encode(response)
        let decoded = try JSONDecoder().decode(RuntimeProbeResponse.self, from: data)
        #expect(decoded == response)
        #expect(decoded.command.rawValue == "diff")
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
