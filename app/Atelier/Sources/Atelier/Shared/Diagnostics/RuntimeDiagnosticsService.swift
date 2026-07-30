import Darwin
import Foundation
import OSLog
import Synchronization

nonisolated final class RuntimeDiagnosticsService: @unchecked Sendable {
    static let shared = RuntimeDiagnosticsService()
    static let eventCapacity = 512
    static let fileMetricCapacity = 128
    /// Backstop for a missed or unarmed mailbox watcher. Stays well inside the
    /// CLI's 3 s probe deadline while costing one `stat` instead of four
    /// open-and-decode attempts per second.
    static let mailboxFallbackInterval = 2.0

    typealias MainSnapshotProvider = @MainActor @Sendable () -> RuntimeMainSnapshot
    typealias ProbeHandler = @MainActor @Sendable (RuntimeProbeRequest) async -> RuntimeProbeResponse

    private let queue = DispatchQueue(label: "app.atelier.runtime-diagnostics", qos: .utility)
    private let clock: RuntimeMonotonicClock
    private let sampler: ProcessMetricsSampling
    private let policy: RuntimeVerdictPolicy
    private let startedAt: Double
    private let cacheDirectory: URL

    private var timer: DispatchSourceTimer?
    private var heartbeat: RuntimeHeartbeatState
    private var cpuDelta = RuntimeCPUDelta()
    private var processSnapshot = RuntimeProcessSnapshot()
    private var mainSnapshot = RuntimeMainSnapshot()
    private var recorder = RuntimeRingBuffer<RuntimeEvent>(capacity: eventCapacity)
    private var liveControllerIDs = Set<String>()
    private var controllerLeakStartedAt: Double?
    private var lastFlushAt = 0.0
    private var lastFlushDurationMs = 0.0
    private var lastWriteError: String?
    private var lastWriteLogAt = 0.0
    private var lastMainHeartbeatWarning = false
    private var isApplicationVisible = true
    private var isHeartbeatPaused = false
    private var lastHeartbeatRequestAt = 0.0
    private var sampleInternally = true
    private var previousWorkspace = RuntimeWorkspaceSnapshot()
    private var mainSnapshotCaptureRequested = true
    private var mainSnapshotProvider: MainSnapshotProvider?
    private var probeHandler: ProbeHandler?
    private var activeProbeID: UUID?
    private var lastHandledProbeID: UUID?
    private var isRuntimeDirectoryPrepared = false
    private var lastFlushedEventSequence = -1
    private var mailboxSource: DispatchSourceFileSystemObject?
    private var lastMailboxCheckAt = 0.0
    private var lastMailboxInode: UInt64 = 0
    private var lastMailboxModification = timespec()

    // Mirrors of queue-owned state that the main actor reads. Reading through
    // `queue.sync` parked the main thread behind whatever the serial queue was
    // doing, which includes snapshot encoding and the atomic snapshot write, so
    // the code measuring main-thread stalls could cause one. A mutex read costs
    // an uncontended lock acquisition instead.
    private let mirroredLastHeartbeatAt: Mutex<Double>
    private let mirroredLiveControllerCount = Mutex<Int>(0)

    init(
        clock: RuntimeMonotonicClock = SystemRuntimeMonotonicClock(),
        sampler: ProcessMetricsSampling = ProcessMetrics(),
        policy: RuntimeVerdictPolicy = .default,
        cacheDirectory: URL? = nil
    ) {
        self.clock = clock
        self.sampler = sampler
        self.policy = policy
        startedAt = clock.now()
        heartbeat = RuntimeHeartbeatState(startedAt: startedAt)
        mirroredLastHeartbeatAt = Mutex(startedAt)
        self.cacheDirectory = cacheDirectory ?? Self.defaultCacheDirectory()
    }

    static func shouldRun(
        arguments: [String] = CommandLine.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        !arguments.contains("--selftest")
            && environment["ATELIER_DISABLE_RUNTIME_DIAGNOSTICS"] != "1"
    }

    @MainActor
    func start(
        sampleInternally: Bool,
        mainSnapshotProvider: @escaping MainSnapshotProvider,
        probeHandler: @escaping ProbeHandler
    ) {
        queue.async { [self] in
            guard timer == nil else { return }
            self.sampleInternally = sampleInternally
            self.mainSnapshotProvider = mainSnapshotProvider
            self.probeHandler = probeHandler
            prepareRuntimeDirectoryIfNeeded()
            armMailboxWatcher()
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .now(), repeating: .milliseconds(250), leeway: .milliseconds(25))
            source.setEventHandler { [weak self] in self?.tick() }
            timer = source
            source.resume()
        }
    }

    func stop() {
        queue.async { [self] in
            timer?.cancel()
            timer = nil
            disarmMailboxWatcher()
            activeProbeID = nil
            mainSnapshotProvider = nil
            probeHandler = nil
        }
    }

    /// Suspends main-thread pings while the window is inactive or occluded. The
    /// reported `heartbeatPaused` flag stays true until the main thread answers
    /// the first ping after resume, so a paused age is never read as a stall.
    func setApplicationVisible(_ isVisible: Bool) {
        queue.async { [self] in
            guard isApplicationVisible != isVisible else { return }
            isApplicationVisible = isVisible
            isHeartbeatPaused = true
            recorder.append(RuntimeEvent(
                monotonicTimeSeconds: clock.now(),
                category: "heartbeat",
                name: isVisible ? "heartbeatResumeRequested" : "heartbeatPaused"
            ))
            // Resume on the next tick instead of waiting out the cadence.
            if isVisible { lastHeartbeatRequestAt = 0 }
        }
    }

    func consumeProcessSample(_ sample: ProcessSample, at time: Double? = nil) {
        queue.async { [self] in
            updateProcess(sample, at: time ?? clock.now())
        }
    }

    func record(
        category: String,
        name: String,
        durationMs: Double? = nil,
        metadata: [String: RuntimeScalar] = [:],
        correlationID: String? = nil
    ) {
        let time = clock.now()
        queue.async { [self] in
            recorder.append(RuntimeEvent(
                monotonicTimeSeconds: time,
                category: category,
                name: name,
                durationMs: durationMs,
                metadata: metadata,
                correlationID: correlationID
            ))
        }
    }

    func registerEditorController(id: String) {
        queue.async { [self] in
            liveControllerIDs.insert(id)
            mirroredLiveControllerCount.withLock { $0 = liveControllerIDs.count }
            recorder.append(RuntimeEvent(
                monotonicTimeSeconds: clock.now(),
                category: "editor",
                name: "nativeEditorInitialized",
                correlationID: id
            ))
        }
    }

    func unregisterEditorController(id: String) {
        queue.async { [self] in
            liveControllerIDs.remove(id)
            mirroredLiveControllerCount.withLock { $0 = liveControllerIDs.count }
            recorder.append(RuntimeEvent(
                monotonicTimeSeconds: clock.now(),
                category: "editor",
                name: "nativeEditorDeinitialized",
                correlationID: id
            ))
        }
    }

    /// Read off the mirror, never through `queue.sync`: both callers are on the
    /// main actor and must not block behind a snapshot flush.
    func currentHeartbeatAgeMilliseconds() -> Double {
        let lastAcknowledgedAt = mirroredLastHeartbeatAt.withLock { $0 }
        return max(0, clock.now() - lastAcknowledgedAt) * 1_000
    }

    func currentLiveControllerCount() -> Int {
        mirroredLiveControllerCount.withLock { $0 }
    }

    private func tick() {
        let now = clock.now()
        let shouldFlush = now - lastFlushAt >= 1
        if shouldFlush { mainSnapshotCaptureRequested = true }
        if RuntimeHeartbeatCadencePolicy.shouldRequest(
            isApplicationVisible: isApplicationVisible,
            needsSnapshotCapture: mainSnapshotCaptureRequested,
            sinceLastRequest: now - lastHeartbeatRequestAt
        ) {
            lastHeartbeatRequestAt = now
            requestHeartbeatIfNeeded()
        }
        // The mailbox is kqueue-driven. Re-arm a watcher that could not attach
        // yet, and keep a bounded fallback check for a missed directory event.
        if mailboxSource == nil {
            prepareRuntimeDirectoryIfNeeded()
            armMailboxWatcher()
        }
        if now - lastMailboxCheckAt >= Self.mailboxFallbackInterval {
            checkMailbox(at: now)
        }
        guard shouldFlush else { return }
        lastFlushAt = now
        if sampleInternally {
            updateProcess(sampler.sample(), at: now)
        }
        flush(at: now)
    }

    private func requestHeartbeatIfNeeded() {
        guard heartbeat.request(), let provider = mainSnapshotProvider else { return }
        let shouldCaptureSnapshot = mainSnapshotCaptureRequested
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let snapshot = shouldCaptureSnapshot ? provider() : nil
            let acknowledgedAt = self.clock.now()
            self.mirroredLastHeartbeatAt.withLock { $0 = acknowledgedAt }
            self.queue.async { [self] in
                heartbeat.acknowledge(at: acknowledgedAt)
                // The main thread answered, so the measurement is live again.
                if isApplicationVisible { isHeartbeatPaused = false }
                if let snapshot {
                    mainSnapshotCaptureRequested = false
                    acceptMainSnapshot(snapshot, at: acknowledgedAt)
                }
            }
        }
    }

    private func acceptMainSnapshot(_ snapshot: RuntimeMainSnapshot, at time: Double) {
        emitWorkspaceTransitions(from: previousWorkspace, to: snapshot.workspace, at: time)
        previousWorkspace = snapshot.workspace
        mainSnapshot = snapshot
    }

    private func emitWorkspaceTransitions(
        from previous: RuntimeWorkspaceSnapshot,
        to current: RuntimeWorkspaceSnapshot,
        at time: Double
    ) {
        if previous.active != current.active {
            recorder.append(RuntimeEvent(
                monotonicTimeSeconds: time,
                category: "workspace",
                name: current.active ? "workspaceActivated" : "workspaceStopped",
                correlationID: current.relativeRootName
            ))
        }
        let previousFiles = Set(previous.fileTabs.map(\.relativePath))
        let currentFiles = Set(current.fileTabs.map(\.relativePath))
        for path in currentFiles.subtracting(previousFiles).sorted() {
            recorder.append(RuntimeEvent(
                monotonicTimeSeconds: time,
                category: "tabs",
                name: "fileTabOpened",
                metadata: ["relativePath": .string(path)]
            ))
        }
        for path in previousFiles.subtracting(currentFiles).sorted() {
            recorder.append(RuntimeEvent(
                monotonicTimeSeconds: time,
                category: "tabs",
                name: "fileTabClosed",
                metadata: ["relativePath": .string(path)]
            ))
        }
        if previous.selectedFileRelativePath != current.selectedFileRelativePath,
           let path = current.selectedFileRelativePath {
            recorder.append(RuntimeEvent(
                monotonicTimeSeconds: time,
                category: "tabs",
                name: "fileTabSelected",
                metadata: ["relativePath": .string(path)]
            ))
        }
    }

    private func updateProcess(_ sample: ProcessSample, at time: Double) {
        processSnapshot = RuntimeProcessSnapshot(
            pid: getpid(),
            uptimeSeconds: max(0, time - startedAt),
            cpuPercent: cpuDelta.consume(sample, at: time),
            cpuTimeSeconds: sample.cpuTimeSeconds,
            physicalFootprintBytes: sample.memoryBytes
        )
    }

    private func flush(at now: Double) {
        let flushStartedAt = clock.now()
        let heartbeatAge = heartbeat.ageMilliseconds(at: now)
        let heartbeatWarning = heartbeatAge >= policy.heartbeatStallMs && !isHeartbeatPaused
        if heartbeatWarning && !lastMainHeartbeatWarning {
            recorder.append(RuntimeEvent(
                monotonicTimeSeconds: now,
                category: "heartbeat",
                name: "mainHeartbeatWarning",
                metadata: ["heartbeatAgeMs": .double(heartbeatAge)]
            ))
        }
        lastMainHeartbeatWarning = heartbeatWarning

        var editor = mainSnapshot.editor
        editor.liveControllerCount = liveControllerIDs.count
        if editor.liveControllerCount > editor.expectedControllerCount {
            if controllerLeakStartedAt == nil { controllerLeakStartedAt = now }
        } else {
            controllerLeakStartedAt = nil
        }
        let leakAge = controllerLeakStartedAt.map { max(0, now - $0) }
        let mainThread = RuntimeMainThreadSnapshot(
            lastHeartbeatAt: heartbeat.lastAcknowledgedAt,
            heartbeatAgeMs: heartbeatAge,
            pendingHeartbeat: heartbeat.pending,
            heartbeatPaused: isHeartbeatPaused
        )
        let verdicts = policy.evaluate(
            process: processSnapshot,
            mainThread: mainThread,
            editor: editor,
            controllerLeakAgeSeconds: leakAge,
            writerError: lastWriteError
        )
        let generatedAt = Self.timestamp()
        let diagnostics = RuntimeDiagnosticsSnapshot(
            eventCount: recorder.elements.count,
            droppedEventCount: recorder.droppedCount,
            lastFlushDurationMs: lastFlushDurationMs,
            lastWriteError: lastWriteError
        )
        let snapshot = RuntimeSnapshot(
            schemaVersion: 1,
            generatedAt: generatedAt,
            monotonicTimeSeconds: now,
            process: processSnapshot,
            mainThread: mainThread,
            workspace: mainSnapshot.workspace,
            editor: editor,
            git: GitCommandExecutor.shared.snapshot(),
            fileTree: mainSnapshot.fileTree,
            terminal: mainSnapshot.terminal,
            diagnostics: diagnostics,
            verdicts: verdicts
        )
        let eventSequence = recorder.sequence
        let signpost = RuntimeSignposts.signposter.beginInterval("RuntimeSnapshotFlush")
        prepareRuntimeDirectoryIfNeeded()
        do {
            try RuntimeAtomicWriter.write(snapshot, to: snapshotURL)
            // An idle app records no events, so re-encoding 512 unchanged
            // entries every second was the dominant diagnostics cost.
            if eventSequence != lastFlushedEventSequence {
                try RuntimeAtomicWriter.write(
                    RuntimeFlightRecorderSnapshot(
                        schemaVersion: 1,
                        generatedAt: generatedAt,
                        events: recorder.elements,
                        droppedEventCount: recorder.droppedCount
                    ),
                    to: flightRecorderURL
                )
                lastFlushedEventSequence = eventSequence
            }
            lastWriteError = nil
        } catch {
            let message = error.localizedDescription
            lastWriteError = message
            // The directory may have been removed underneath us; recreate it
            // on the next flush instead of failing forever.
            isRuntimeDirectoryPrepared = false
            recorder.append(RuntimeEvent(
                monotonicTimeSeconds: now,
                category: "diagnostics",
                name: "snapshotFlushFailed",
                metadata: ["error": .string(message)]
            ))
            if now - lastWriteLogAt >= 60 {
                lastWriteLogAt = now
                AppLogger.runtimeDiagnostics.error(
                    "Runtime snapshot write failed: \(message, privacy: .public)"
                )
            }
        }
        RuntimeSignposts.signposter.endInterval("RuntimeSnapshotFlush", signpost)
        lastFlushDurationMs = max(0, clock.now() - flushStartedAt) * 1_000
    }

    private func prepareRuntimeDirectoryIfNeeded() {
        guard !isRuntimeDirectoryPrepared else { return }
        do {
            try RuntimeAtomicWriter.prepareDirectory(for: snapshotURL)
            isRuntimeDirectoryPrepared = true
        } catch {
            isRuntimeDirectoryPrepared = false
        }
    }

    /// Watches the mailbox directory instead of polling it. `atelier-doctor`
    /// renames `request.json` into place, so a directory write event covers both
    /// the first request and every replacement.
    private func armMailboxWatcher() {
        guard mailboxSource == nil, isRuntimeDirectoryPrepared else { return }
        let directoryPath = requestURL.deletingLastPathComponent().path
        let descriptor = open(directoryPath, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .revoke],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            guard let self, let events = mailboxSource?.data else { return }
            if events.contains(.write) {
                checkMailbox(at: clock.now())
            }
            if !events.intersection([.delete, .rename, .revoke]).isEmpty {
                disarmMailboxWatcher()
                isRuntimeDirectoryPrepared = false
            }
        }
        source.setCancelHandler { close(descriptor) }
        mailboxSource = source
        source.resume()
        checkMailbox(at: clock.now())
    }

    private func disarmMailboxWatcher() {
        mailboxSource?.cancel()
        mailboxSource = nil
    }

    /// True only when `request.json` appeared or was replaced since the last
    /// check, so the idle path costs one `stat` and never decodes JSON.
    private func mailboxRequestChanged() -> Bool {
        var info = Darwin.stat()
        guard stat(requestURL.path, &info) == 0 else {
            lastMailboxInode = 0
            return false
        }
        let inode = UInt64(info.st_ino)
        let modification = info.st_mtimespec
        guard inode != lastMailboxInode
            || modification.tv_sec != lastMailboxModification.tv_sec
            || modification.tv_nsec != lastMailboxModification.tv_nsec else { return false }
        lastMailboxInode = inode
        lastMailboxModification = modification
        return true
    }

    private func checkMailbox(at now: Double) {
        lastMailboxCheckAt = now
        guard activeProbeID == nil,
              mailboxRequestChanged(),
              let data = try? Data(contentsOf: requestURL),
              let request = try? JSONDecoder().decode(RuntimeProbeRequest.self, from: data),
              request.schemaVersion == 1,
              request.id != lastHandledProbeID,
              let probeHandler else { return }
        activeProbeID = request.id
        let started = now
        queue.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.activeProbeID == request.id else { return }
            let response = RuntimeProbeResponse(
                schemaVersion: 1,
                id: request.id,
                command: request.command,
                status: "timeout",
                completedAt: Self.timestamp(),
                elapsedMs: max(0, self.clock.now() - started) * 1_000,
                result: [
                    "heartbeatAgeMs": .double(self.heartbeat.ageMilliseconds(at: self.clock.now()))
                ],
                editor: nil,
                error: "Main actor did not acknowledge the probe before timeout."
            )
            self.finishProbe(response)
        }
        Task { @MainActor [weak self] in
            let response = await probeHandler(request)
            self?.queue.async { [weak self] in
                guard let self, self.activeProbeID == request.id else { return }
                self.finishProbe(response)
            }
        }
    }

    private func finishProbe(_ response: RuntimeProbeResponse) {
        do {
            try RuntimeAtomicWriter.write(response, to: responseURL)
        } catch {
            AppLogger.runtimeDiagnostics.error(
                "Runtime probe response write failed: \(error.localizedDescription, privacy: .public)"
            )
        }
        recorder.append(RuntimeEvent(
            monotonicTimeSeconds: clock.now(),
            category: "probe",
            name: response.command.rawValue,
            durationMs: response.elapsedMs,
            metadata: ["status": .string(response.status)],
            correlationID: response.id.uuidString
        ))
        lastHandledProbeID = response.id
        activeProbeID = nil
    }

    private var snapshotURL: URL {
        cacheDirectory.appending(path: "Runtime/current/snapshot.json")
    }

    private var flightRecorderURL: URL {
        cacheDirectory.appending(path: "Runtime/current/flight-recorder.json")
    }

    private var requestURL: URL {
        cacheDirectory.appending(path: "Runtime/current/request.json")
    }

    private var responseURL: URL {
        cacheDirectory.appending(path: "Runtime/current/response.json")
    }

    private static func defaultCacheDirectory() -> URL {
        let manager = FileManager.default
        let base = (try? manager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? manager.temporaryDirectory
        return base.appending(path: Bundle.main.bundleIdentifier ?? "app.atelier.Atelier", directoryHint: .isDirectory)
    }

    private static func timestamp() -> String {
        Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true).timeZone(separator: .colon))
    }
}
