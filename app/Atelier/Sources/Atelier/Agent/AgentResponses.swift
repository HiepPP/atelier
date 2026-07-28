import CoreServices
import Foundation
import Observation

nonisolated enum AgentProvider: String, Sendable {
    case codex = "Codex"
    case claude = "Claude"
}

nonisolated struct AgentSessionIdentity: Identifiable, Hashable, Sendable {
    let provider: AgentProvider
    let sessionID: String

    var id: String {
        "\(provider.rawValue.lowercased()):\(sessionID)"
    }
}

nonisolated struct AgentResponse: Identifiable, Equatable, Sendable {
    let id: String
    let provider: AgentProvider
    let sessionID: String
    let timestamp: Date
    let markdown: String

    var session: AgentSessionIdentity {
        AgentSessionIdentity(provider: provider, sessionID: sessionID)
    }

    var readIdentity: AgentResponseReadIdentity {
        AgentResponseReadIdentity(session: session, responseID: id)
    }
}

nonisolated struct AgentResponseReadIdentity: Hashable, Sendable {
    let session: AgentSessionIdentity
    let responseID: String
}

nonisolated struct AgentSessionSummary: Identifiable, Equatable, Sendable {
    let session: AgentSessionIdentity
    let latestResponseTime: Date
    let responseCount: Int
    let unreadCount: Int

    var id: String { session.id }

    var provider: AgentProvider { session.provider }

    var sessionID: String { session.sessionID }
}

nonisolated protocol AgentResponseSource: Sendable {
    func loadResponses() async -> [AgentResponse]
    func watchedRoots() async -> [URL]
    func watchedPathPrefixes() async -> [String]
}

nonisolated extension AgentResponseSource {
    func watchedRoots() async -> [URL] { [] }
    func watchedPathPrefixes() async -> [String] { [] }
}

nonisolated enum AgentTranscriptParser {
    struct State: Sendable {
        var codexWorkspace: String?
        var codexSessionID: String?
        var pendingData = Data()
    }

    struct ParseResult: Sendable {
        let responses: [AgentResponse]
        let state: State
    }

    static func extractAll(
        from jsonLines: String,
        workspacePath: String,
        sourceID: String,
        modifiedAfter: Date
    ) -> [AgentResponse] {
        let data = Data(jsonLines.utf8)
        let responses = parse(
            data: data,
            workspacePath: workspacePath,
            sourceID: sourceID,
            modifiedAfter: modifiedAfter,
            state: State()
        )?.responses ?? []
        return responses.sorted {
            $0.timestamp == $1.timestamp ? $0.id < $1.id : $0.timestamp < $1.timestamp
        }
    }

    static func parse(
        data: Data,
        workspacePath: String,
        sourceID: String,
        modifiedAfter: Date,
        state initialState: State
    ) -> ParseResult? {
        let expectedWorkspace = standardizedPath(workspacePath)
        let timestampParser = TimestampParser()
        var state = initialState
        var buffer = state.pendingData
        buffer.append(data)
        state.pendingData.removeAll(keepingCapacity: false)
        var responses: [AgentResponse] = []
        var lineStart = buffer.startIndex
        var lineCount = 0

        for index in buffer.indices where buffer[index] == 0x0A {
            lineCount &+= 1
            if lineCount.isMultiple(of: 256), isCurrentTaskCancelled { return nil }
            if index > lineStart,
               let object = decodeObject(Data(buffer[lineStart..<index])) {
                consume(
                    object,
                    expectedWorkspace: expectedWorkspace,
                    sourceID: sourceID,
                    modifiedAfter: modifiedAfter,
                    timestampParser: timestampParser,
                    state: &state,
                    responses: &responses
                )
            }
            lineStart = buffer.index(after: index)
        }

        if lineStart < buffer.endIndex {
            let trailing = Data(buffer[lineStart...])
            if let object = decodeObject(trailing) {
                consume(
                    object,
                    expectedWorkspace: expectedWorkspace,
                    sourceID: sourceID,
                    modifiedAfter: modifiedAfter,
                    timestampParser: timestampParser,
                    state: &state,
                    responses: &responses
                )
            } else {
                state.pendingData = trailing
            }
        }

        guard !isCurrentTaskCancelled else { return nil }
        return ParseResult(responses: responses, state: state)
    }

    static func belongsToWorkspace(_ jsonLines: String, workspacePath: String) -> Bool {
        guard let declared = declaredWorkspacePath(jsonLines) else { return false }
        return declared == standardizedPath(workspacePath)
    }

    /// True only when the lines name a workspace and it is a different one.
    /// Lines that name no workspace return false, so an unknown answer never
    /// drops a real transcript.
    static func declaresOtherWorkspace(_ jsonLines: String, workspacePath: String) -> Bool {
        guard let declared = declaredWorkspacePath(jsonLines) else { return false }
        return declared != standardizedPath(workspacePath)
    }

    private static func declaredWorkspacePath(_ jsonLines: String) -> String? {
        for line in jsonLines.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            if object["type"] as? String == "session_meta",
               let payload = object["payload"] as? [String: Any],
               let cwd = payload["cwd"] as? String {
                return standardizedPath(cwd)
            }
            if let cwd = object["cwd"] as? String {
                return standardizedPath(cwd)
            }
        }
        return nil
    }

    static func sessionStartedAt(_ jsonLines: String) -> Date? {
        let timestampParser = TimestampParser()
        for line in jsonLines.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let timestamp = object["timestamp"] as? String,
                  let date = timestampParser.date(from: timestamp) else {
                continue
            }
            return date
        }
        return nil
    }

    private static func consume(
        _ object: [String: Any],
        expectedWorkspace: String,
        sourceID: String,
        modifiedAfter: Date,
        timestampParser: TimestampParser,
        state: inout State,
        responses: inout [AgentResponse]
    ) {
        if object["type"] as? String == "session_meta",
           let payload = object["payload"] as? [String: Any] {
            if let cwd = payload["cwd"] as? String {
                state.codexWorkspace = standardizedPath(cwd)
            }
            state.codexSessionID = payload["id"] as? String
            return
        }

        let provider: AgentProvider
        let sessionID: String
        let markdown: String

        if state.codexWorkspace == expectedWorkspace,
           let content = codexAssistantText(from: object) {
            provider = .codex
            sessionID = state.codexSessionID ?? fallbackSessionID(
                provider: .codex,
                workspacePath: expectedWorkspace,
                sourceID: sourceID
            )
            markdown = content
        } else if let content = claudeAssistantText(from: object),
                  let cwd = object["cwd"] as? String,
                  standardizedPath(cwd) == expectedWorkspace {
            provider = .claude
            sessionID = object["sessionId"] as? String ?? fallbackSessionID(
                provider: .claude,
                workspacePath: expectedWorkspace,
                sourceID: sourceID
            )
            markdown = content
        } else {
            return
        }

        guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let timestamp = object["timestamp"] as? String,
              let date = timestampParser.date(from: timestamp),
              date >= modifiedAfter else {
            return
        }
        responses.append(AgentResponse(
            id: stableID(
                provider: provider,
                sessionID: sessionID,
                recordID: recordID(from: object),
                timestamp: timestamp,
                markdown: markdown
            ),
            provider: provider,
            sessionID: sessionID,
            timestamp: date,
            markdown: markdown
        ))
    }

    private static func decodeObject(_ data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func codexAssistantText(from object: [String: Any]) -> String? {
        guard object["type"] as? String == "response_item",
              let payload = object["payload"] as? [String: Any],
              payload["type"] as? String == "message",
              payload["role"] as? String == "assistant",
              payload["phase"] as? String == "final_answer",
              let content = payload["content"] as? [[String: Any]] else {
            return nil
        }
        return content.compactMap { item in
            guard item["type"] as? String == "output_text" else { return nil }
            return item["text"] as? String
        }.joined(separator: "\n")
    }

    private static func claudeAssistantText(from object: [String: Any]) -> String? {
        guard object["type"] as? String == "assistant",
              let message = object["message"] as? [String: Any],
              message["role"] as? String == "assistant",
              message["stop_reason"] as? String == "end_turn",
              let content = message["content"] as? [[String: Any]] else {
            return nil
        }
        return content.compactMap { item in
            guard item["type"] as? String == "text" else { return nil }
            return item["text"] as? String
        }.joined(separator: "\n")
    }

    private static func recordID(from object: [String: Any]) -> String? {
        if let id = object["uuid"] as? String { return id }
        if let id = object["id"] as? String { return id }
        if let payload = object["payload"] as? [String: Any],
           let id = payload["id"] as? String {
            return id
        }
        return nil
    }

    private static func stableID(
        provider: AgentProvider,
        sessionID: String,
        recordID: String?,
        timestamp: String,
        markdown: String
    ) -> String {
        let recordComponent = recordID ?? deterministicDigest("\(timestamp)\u{1f}\(markdown)")
        return "\(provider.rawValue.lowercased()):\(sessionID):\(recordComponent)"
    }

    static func fallbackSessionID(
        provider: AgentProvider,
        workspacePath: String,
        sourceID: String
    ) -> String {
        let seed = [
            provider.rawValue.lowercased(),
            standardizedPath(workspacePath),
            standardizedSourceID(sourceID)
        ].joined(separator: "\u{1f}")
        return "local-\(deterministicDigest(seed))"
    }

    private static func standardizedSourceID(_ sourceID: String) -> String {
        guard sourceID.hasPrefix("/") else { return sourceID }
        return standardizedPath(sourceID)
    }

    private static func deterministicDigest(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    private final class TimestampParser {
        private let fractional: ISO8601DateFormatter
        private let standard = ISO8601DateFormatter()

        init() {
            fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        }

        func date(from value: String) -> Date? {
            fractional.date(from: value) ?? standard.date(from: value)
        }
    }

    private static var isCurrentTaskCancelled: Bool {
        withUnsafeCurrentTask { task in
            task?.isCancelled == true
        }
    }

    private static func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }
}

private nonisolated final class AgentTranscriptRestoreGate: @unchecked Sendable {
    static let shared = AgentTranscriptRestoreGate()

    private let lock = NSLock()
    private var isHeld = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if isHeld {
                waiters.append(continuation)
                lock.unlock()
            } else {
                isHeld = true
                lock.unlock()
                continuation.resume()
            }
        }
    }

    func release() {
        lock.lock()
        if waiters.isEmpty {
            isHeld = false
            lock.unlock()
            return
        }
        let waiter = waiters.removeFirst()
        lock.unlock()
        waiter.resume()
    }
}

nonisolated actor AgentTranscriptMonitor: AgentResponseSource {
    private static let maximumTranscriptBytes = 16 * 1024 * 1024
    private static let workspaceProbeBytes = 16 * 1024
    private static let maximumFirstParseBytes = 1024 * 1024
    /// How far back the response overlay restores. Transcripts older than this
    /// window are never opened, and older responses never reach the panel.
    static let defaultHistoryWindow: TimeInterval = 3 * 24 * 60 * 60

    private struct TranscriptEntry {
        let url: URL
        let modificationDate: Date
        let isDirectory: Bool
        let isRegularFile: Bool
        let fileSize: Int
    }

    private struct CachedTranscript {
        let modificationDate: Date
        let size: Int
        let fileID: UInt64
        let parserState: AgentTranscriptParser.State
        let responses: [AgentResponse]
    }

    private struct FileFingerprint: Equatable {
        let url: URL
        let size: Int
        let modificationDate: Date
    }

    private let workspacePath: String
    private let modifiedAfter: Date
    private let roots: [URL]
    private let watchRoots: [URL]
    private let responseLimit: Int
    private let transcriptLimitPerRoot: Int
    private let uncachedBytesLimit: Int
    private var directoryLimitPerRoot: Int { transcriptLimitPerRoot * 4 }
    private var discoveredURLs: [URL] = []
    private var cache: [URL: CachedTranscript] = [:]
    private var foreignURLs: Set<URL> = []
    private var nextDiscoveryDate = Date.distantPast
    private var hasCompletedInitialLoad = false
    private var lastFingerprints: [FileFingerprint] = []
    private var lastMergedResponses: [AgentResponse] = []
    private var hasMergedResult = false
    private(set) var parsedByteCount = 0
    private(set) var mergeCount = 0

    init(
        workspacePath: String,
        modifiedAfter: Date = .distantPast,
        roots: [URL]? = nil,
        responseLimit: Int = 100,
        transcriptLimitPerRoot: Int = 100,
        uncachedBytesLimit: Int = 16 * 1024 * 1024
    ) {
        self.workspacePath = workspacePath
        self.modifiedAfter = modifiedAfter
        self.responseLimit = max(1, responseLimit)
        self.transcriptLimitPerRoot = max(1, transcriptLimitPerRoot)
        self.uncachedBytesLimit = max(1, uncachedBytesLimit)
        if let roots {
            self.roots = roots
            self.watchRoots = roots
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let codexSessions = home.appendingPathComponent(".codex/sessions", isDirectory: true)
            let claudeProjects = home.appendingPathComponent(".claude/projects", isDirectory: true)
            // Claude Code stores transcripts per workspace in a directory named
            // after the workspace path with non-alphanumeric characters mapped
            // to "-". Scanning only that directory avoids enumerating every
            // project's transcripts on each refresh.
            let munged = Self.mungedProjectDirectoryName(for: workspacePath)
            self.roots = [
                codexSessions,
                claudeProjects.appendingPathComponent(munged, isDirectory: true)
            ]
            // Watch the parent so transcripts for a brand-new workspace
            // directory still trigger a refresh.
            self.watchRoots = [codexSessions, claudeProjects]
        }
    }

    private static func mungedProjectDirectoryName(for workspacePath: String) -> String {
        let standardized = URL(fileURLWithPath: workspacePath)
            .standardizedFileURL.resolvingSymlinksInPath().path
        return String(standardized.map { character in
            character.isLetter || character.isNumber ? character : "-"
        })
    }

    func watchedRoots() async -> [URL] {
        watchRoots.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func watchedPathPrefixes() async -> [String] {
        roots.map(\.path)
    }

    func loadResponses() async -> [AgentResponse] {
        guard !hasCompletedInitialLoad else {
            return loadResponsesWithoutInitialGate()
        }

        await AgentTranscriptRestoreGate.shared.acquire()
        let responses = loadResponsesWithoutInitialGate()
        hasCompletedInitialLoad = true
        AgentTranscriptRestoreGate.shared.release()
        return responses
    }

    private func loadResponsesWithoutInitialGate() -> [AgentResponse] {
        if Date() >= nextDiscoveryDate {
            discoveredURLs = transcriptURLs()
            nextDiscoveryDate = Date().addingTimeInterval(2)
            let activeURLs = Set(discoveredURLs)
            cache = cache.filter { activeURLs.contains($0.key) }
            foreignURLs.formIntersection(activeURLs)
        }

        // Fingerprint every discovered file with one cheap size and
        // modification date read. A running agent appends to one transcript,
        // so most refreshes see no change at all. Returning the stored result
        // then skips the full attribute read, the parse, and the merge.
        var fingerprints: [FileFingerprint] = []
        fingerprints.reserveCapacity(discoveredURLs.count)
        for url in discoveredURLs {
            guard !isCurrentTaskCancelled else { return [] }
            // One stat call per file. URL resource values cache their result on
            // the URL, so an appended file would keep reporting its old size.
            var info = stat()
            guard stat(url.path, &info) == 0 else { continue }
            fingerprints.append(
                FileFingerprint(
                    url: url,
                    size: Int(info.st_size),
                    modificationDate: Self.modificationDate(from: info)
                )
            )
        }
        if hasMergedResult, fingerprints == lastFingerprints {
            return lastMergedResponses
        }

        var responses: [AgentResponse] = []
        var remainingUncachedBytes = uncachedBytesLimit

        for fingerprint in fingerprints {
            guard !isCurrentTaskCancelled else { return [] }
            // Files arrive newest first. Once the newest responses fill the
            // limit, older transcripts cannot reach the published list, so
            // opening them only burns CPU on a large backlog.
            guard responses.count < responseLimit else { break }
            let url = fingerprint.url
            // A session that belongs to another workspace can never produce a
            // response here. Skip it before any read, however much it grows.
            if foreignURLs.contains(url) { continue }
            // An unchanged file keeps its cached responses. Only a file whose
            // size or modification date moved needs the full attribute read.
            if let cached = cache[url],
               cached.size == fingerprint.size,
               cached.modificationDate == fingerprint.modificationDate {
                responses.append(contentsOf: cached.responses)
                continue
            }
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = (attributes[.size] as? NSNumber)?.intValue,
                  size <= Self.maximumTranscriptBytes,
                  let fileNumber = attributes[.systemFileNumber] as? NSNumber else {
                continue
            }
            // Store the fingerprint date, not the attribute date, so the next
            // refresh compares two dates read the same way.
            let modificationDate = fingerprint.modificationDate
            let fileID = fileNumber.uint64Value
            if let cached = cache[url],
               cached.size == size,
               cached.fileID == fileID {
                if cached.modificationDate != modificationDate {
                    cache[url] = CachedTranscript(
                        modificationDate: modificationDate,
                        size: cached.size,
                        fileID: cached.fileID,
                        parserState: cached.parserState,
                        responses: cached.responses
                    )
                }
                responses.append(contentsOf: cached.responses)
                continue
            }

            let previous = cache[url]
            // Read only the head before the first parse of a file. A head that
            // names another workspace means the whole file is waste here.
            if previous == nil, declaresOtherWorkspace(at: url) {
                foreignURLs.insert(url)
                continue
            }
            let canReadAppend = previous?.fileID == fileID && size > (previous?.size ?? size)
            // A first read of a large transcript only needs the newest part.
            // Older lines in the same file cannot reach the response limit.
            let firstReadOffset = canReadAppend || size <= Self.maximumFirstParseBytes
                ? 0
                : size - Self.maximumFirstParseBytes
            let offset = canReadAppend ? previous?.size ?? 0 : firstReadOffset
            let uncachedBytes = size - offset
            guard uncachedBytes <= remainingUncachedBytes else {
                continue
            }
            guard let tail = readData(from: url, offset: offset) else {
                continue
            }
            remainingUncachedBytes -= tail.count
            // Keep the true end offset for the cache. A capped read drops bytes
            // from the front of the buffer, and a later append must still start
            // at the real end of the file.
            let endOffset = offset + tail.count
            let data = firstReadOffset > 0 ? cappedParseBuffer(for: url, tail: tail) : tail
            parsedByteCount &+= data.count
            let initialState = canReadAppend
                ? previous?.parserState ?? AgentTranscriptParser.State()
                : AgentTranscriptParser.State()
            guard let result = AgentTranscriptParser.parse(
                data: data,
                workspacePath: workspacePath,
                sourceID: url.path,
                modifiedAfter: modifiedAfter,
                state: initialState
            ) else { return [] }
            var parsed = canReadAppend ? previous?.responses ?? [] : []
            parsed.append(contentsOf: result.responses)
            parsed.sort {
                $0.timestamp == $1.timestamp ? $0.id < $1.id : $0.timestamp < $1.timestamp
            }
            if parsed.count > responseLimit {
                parsed.removeFirst(parsed.count - responseLimit)
            }
            cache[url] = CachedTranscript(
                modificationDate: modificationDate,
                size: endOffset,
                fileID: fileID,
                parserState: result.state,
                responses: parsed
            )
            responses.append(contentsOf: parsed)
        }

        var unique: [String: AgentResponse] = [:]
        for response in responses {
            unique[response.id] = response
        }
        let sorted = unique.values.sorted {
            $0.timestamp == $1.timestamp ? $0.id < $1.id : $0.timestamp < $1.timestamp
        }
        let merged = Array(sorted.suffix(responseLimit))
        mergeCount += 1
        lastFingerprints = fingerprints
        lastMergedResponses = merged
        hasMergedResult = true
        return merged
    }

    /// Buffer for a capped first read: the file head, then the tail started at
    /// its first complete line. The head carries the codex `session_meta` line,
    /// and a response is only accepted while that session workspace is known.
    private func cappedParseBuffer(for url: URL, tail: Data) -> Data {
        var buffer = Data()
        if let head = readHead(of: url), let lastNewline = head.lastIndex(of: 0x0A) {
            buffer.append(head[...lastNewline])
        }
        if let firstNewline = tail.firstIndex(of: 0x0A) {
            buffer.append(tail[tail.index(after: firstNewline)...])
        }
        return buffer
    }

    private func readHead(of url: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return try? handle.read(upToCount: Self.workspaceProbeBytes)
    }

    private func declaresOtherWorkspace(at url: URL) -> Bool {
        guard let head = readHead(of: url) else { return false }
        return AgentTranscriptParser.declaresOtherWorkspace(
            String(decoding: head, as: UTF8.self),
            workspacePath: workspacePath
        )
    }

    private static func modificationDate(from info: stat) -> Date {
        Date(
            timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec)
                + TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000
        )
    }

    private func readData(from url: URL, offset: Int) -> Data? {
        guard offset > 0 else { return try? Data(contentsOf: url) }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: UInt64(offset))
            return try handle.readToEnd() ?? Data()
        } catch {
            return nil
        }
    }

    private var isCurrentTaskCancelled: Bool {
        withUnsafeCurrentTask { task in
            task?.isCancelled == true
        }
    }

    private func transcriptURLs() -> [URL] {
        var candidates: [TranscriptEntry] = []
        let keys: Set<URLResourceKey> = [
            .contentModificationDateKey,
            .fileSizeKey,
            .isDirectoryKey,
            .isRegularFileKey
        ]

        for root in roots where FileManager.default.fileExists(atPath: root.path) {
            var rootCandidates: [TranscriptEntry] = []
            var visitedDirectoryCount = 0
            collectRecentTranscriptEntries(
                in: root,
                keys: keys,
                entries: &rootCandidates,
                visitedDirectoryCount: &visitedDirectoryCount
            )
            candidates.append(contentsOf: rootCandidates)
        }
        return candidates.sorted(by: Self.isNewerEntry).map(\.url)
    }

    private func collectRecentTranscriptEntries(
        in directory: URL,
        keys: Set<URLResourceKey>,
        entries: inout [TranscriptEntry],
        visitedDirectoryCount: inout Int
    ) {
        guard entries.count < transcriptLimitPerRoot,
              visitedDirectoryCount < directoryLimitPerRoot,
              !isCurrentTaskCancelled else {
            return
        }
        visitedDirectoryCount += 1

        guard let children = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return }
        let childEntries = children.compactMap { url -> TranscriptEntry? in
            guard let values = try? url.resourceValues(forKeys: keys),
                  let modificationDate = values.contentModificationDate else {
                return nil
            }
            return TranscriptEntry(
                url: url,
                modificationDate: modificationDate,
                isDirectory: values.isDirectory == true,
                isRegularFile: values.isRegularFile == true,
                fileSize: values.fileSize ?? 0
            )
        }.sorted(by: Self.isNewerEntry)

        for entry in childEntries where entries.count < transcriptLimitPerRoot {
            if entry.isDirectory {
                collectRecentTranscriptEntries(
                    in: entry.url,
                    keys: keys,
                    entries: &entries,
                    visitedDirectoryCount: &visitedDirectoryCount
                )
            } else if entry.isRegularFile,
                      entry.url.pathExtension == "jsonl",
                      entry.modificationDate >= modifiedAfter,
                      entry.fileSize <= Self.maximumTranscriptBytes {
                entries.append(entry)
            }
        }
    }

    private static func isNewerEntry(
        _ lhs: TranscriptEntry,
        _ rhs: TranscriptEntry
    ) -> Bool {
        if lhs.modificationDate == rhs.modificationDate {
            return lhs.url.path > rhs.url.path
        }
        return lhs.modificationDate > rhs.modificationDate
    }
}

nonisolated final class TranscriptDirectoryWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "atelier.agent-transcript-watcher")
    private let handler: @Sendable () -> Void
    private let pathPrefixes: [String]

    init?(roots: [URL], pathPrefixes: [String], handler: @escaping @Sendable () -> Void) {
        self.handler = handler
        self.pathPrefixes = pathPrefixes.map { $0.hasSuffix("/") ? $0 : $0 + "/" }
        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()
        let callback: FSEventStreamCallback = { _, info, eventCount, eventPaths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<TranscriptDirectoryWatcher>
                .fromOpaque(info)
                .takeUnretainedValue()
            guard let paths = unsafeBitCast(eventPaths, to: CFArray.self) as? [String] else {
                watcher.handler()
                return
            }
            guard eventCount > 0 else { return }
            if watcher.matches(paths) {
                watcher.handler()
            }
        }
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            roots.map(\.path) as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents
            )
        ) else { return nil }
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return nil
        }
        self.stream = stream
    }

    private func matches(_ paths: [String]) -> Bool {
        guard !pathPrefixes.isEmpty else { return true }
        return paths.contains { path in
            pathPrefixes.contains { prefix in
                path.hasPrefix(prefix) || path + "/" == prefix
            }
        }
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit {
        stop()
    }
}

@MainActor
@Observable
final class AgentResponsesModel {
    private(set) var responses: [AgentResponse] = []
    private(set) var isMonitoring = false
    private(set) var isRefreshing = false
    private(set) var selectedSession: AgentSessionIdentity?

    private let source: any AgentResponseSource
    private var responseIDs: Set<AgentResponseReadIdentity> = []
    private var readResponseIDs: Set<AgentResponseReadIdentity> = []
    private var monitorTask: Task<Void, Never>?
    private var watcher: TranscriptDirectoryWatcher?
    private var debouncedRefreshTask: Task<Void, Never>?
    private var trailingRefreshTask: Task<Void, Never>?
    private var isRefreshInFlight = false

    var unreadCount: Int {
        responses.reduce(into: 0) { count, response in
            if !readResponseIDs.contains(response.readIdentity) {
                count += 1
            }
        }
    }

    var sessionSummaries: [AgentSessionSummary] {
        let grouped = Dictionary(grouping: responses, by: \.session)
        return grouped.compactMap { session, sessionResponses in
            guard let latest = sessionResponses.map(\.timestamp).max() else { return nil }
            return AgentSessionSummary(
                session: session,
                latestResponseTime: latest,
                responseCount: sessionResponses.count,
                unreadCount: sessionResponses.reduce(into: 0) { count, response in
                    if !readResponseIDs.contains(response.readIdentity) {
                        count += 1
                    }
                }
            )
        }.sorted {
            if $0.latestResponseTime == $1.latestResponseTime {
                return $0.id < $1.id
            }
            return $0.latestResponseTime > $1.latestResponseTime
        }
    }

    var sessions: [AgentSessionIdentity] {
        sessionSummaries.map(\.session)
    }

    var selectedResponses: [AgentResponse] {
        guard let selectedSession else { return [] }
        return responses.filter { $0.session == selectedSession }
    }

    init(source: any AgentResponseSource) {
        self.source = source
    }

    func start() {
        guard monitorTask == nil else { return }
        isMonitoring = true
        monitorTask = Task { [weak self] in
            await self?.refresh(showProgress: false, markLoadedResponsesRead: true)
            guard !Task.isCancelled else { return }
            await self?.startWatching()
        }
    }

    private func startWatching() async {
        let roots = await source.watchedRoots()
        let prefixes = await source.watchedPathPrefixes()
        guard isMonitoring, watcher == nil, !roots.isEmpty else { return }
        watcher = TranscriptDirectoryWatcher(roots: roots, pathPrefixes: prefixes) { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleWatcherEvent()
            }
        }
    }

    private func handleWatcherEvent() {
        guard isMonitoring else { return }
        // Collapse the burst before refreshing. A running agent writes its own
        // transcript continuously, and refreshing per event re-walked and
        // re-parsed every transcript file back to back.
        debouncedRefreshTask?.cancel()
        debouncedRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await self?.refresh(showProgress: false, markLoadedResponsesRead: false)
        }
        // Transcript discovery inside the source is throttled; a trailing
        // refresh picks up files created during the throttle window when no
        // further filesystem event follows.
        trailingRefreshTask?.cancel()
        trailingRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await self?.refresh(showProgress: false, markLoadedResponsesRead: false)
        }
    }

    func stop() {
        monitorTask?.cancel()
        monitorTask = nil
        debouncedRefreshTask?.cancel()
        debouncedRefreshTask = nil
        trailingRefreshTask?.cancel()
        trailingRefreshTask = nil
        watcher?.stop()
        watcher = nil
        isMonitoring = false
    }

    func refresh() async {
        await refresh(showProgress: true, markLoadedResponsesRead: false)
    }

    private func refresh(
        showProgress: Bool,
        markLoadedResponsesRead: Bool
    ) async {
        guard !isRefreshInFlight else { return }
        isRefreshInFlight = true
        if showProgress { isRefreshing = true }
        defer {
            isRefreshInFlight = false
            if showProgress { isRefreshing = false }
        }

        let loaded = await source.loadResponses()
        guard !Task.isCancelled else { return }
        if markLoadedResponsesRead {
            readResponseIDs.formUnion(loaded.map(\.readIdentity))
        }
        let newResponses = loaded.filter { responseIDs.insert($0.readIdentity).inserted }
        guard !newResponses.isEmpty else { return }
        responses.append(contentsOf: newResponses)
        responses.sort {
            $0.timestamp == $1.timestamp ? $0.id < $1.id : $0.timestamp < $1.timestamp
        }
        // Bound retained transcript memory across long monitoring sessions.
        if responses.count > 300 {
            responses.removeFirst(responses.count - 300)
        }
        if selectedSession == nil {
            selectedSession = sessionSummaries.first?.session
        }
    }

    func selectSession(_ session: AgentSessionIdentity?) {
        guard let session else {
            selectedSession = nil
            return
        }
        guard sessionSummaries.contains(where: { $0.session == session }) else { return }
        selectedSession = session
    }

    func markRead(_ response: AgentResponse) {
        guard responseIDs.contains(response.readIdentity) else { return }
        readResponseIDs.insert(response.readIdentity)
    }

    func markRead(_ visibleResponses: some Sequence<AgentResponse>) {
        for response in visibleResponses {
            markRead(response)
        }
    }

    isolated deinit {
        stop()
    }
}
