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
}

nonisolated enum AgentTranscriptParser {
    static func extractAll(
        from jsonLines: String,
        workspacePath: String,
        sourceID: String,
        modifiedAfter: Date
    ) -> [AgentResponse] {
        let expectedWorkspace = standardizedPath(workspacePath)
        var codexWorkspace: String?
        var codexSessionID: String?
        var responses: [AgentResponse] = []

        for line in jsonLines.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            if object["type"] as? String == "session_meta",
               let payload = object["payload"] as? [String: Any] {
                if let cwd = payload["cwd"] as? String {
                    codexWorkspace = standardizedPath(cwd)
                }
                codexSessionID = payload["id"] as? String
                continue
            }

            guard let timestamp = object["timestamp"] as? String,
                  let date = parseDate(timestamp),
                  date >= modifiedAfter else {
                continue
            }

            let response: AgentResponse?
            if codexWorkspace == expectedWorkspace,
               let markdown = codexAssistantText(from: object) {
                let sessionID = codexSessionID ?? fallbackSessionID(
                    provider: .codex,
                    workspacePath: expectedWorkspace,
                    sourceID: sourceID
                )
                response = AgentResponse(
                    id: stableID(
                        provider: .codex,
                        sessionID: sessionID,
                        recordID: recordID(from: object),
                        timestamp: timestamp,
                        markdown: markdown
                    ),
                    provider: .codex,
                    sessionID: sessionID,
                    timestamp: date,
                    markdown: markdown
                )
            } else if let cwd = object["cwd"] as? String,
                      standardizedPath(cwd) == expectedWorkspace,
                      let markdown = claudeAssistantText(from: object) {
                let sessionID = object["sessionId"] as? String ?? fallbackSessionID(
                    provider: .claude,
                    workspacePath: expectedWorkspace,
                    sourceID: sourceID
                )
                response = AgentResponse(
                    id: stableID(
                        provider: .claude,
                        sessionID: sessionID,
                        recordID: recordID(from: object),
                        timestamp: timestamp,
                        markdown: markdown
                    ),
                    provider: .claude,
                    sessionID: sessionID,
                    timestamp: date,
                    markdown: markdown
                )
            } else {
                response = nil
            }

            if let response, !response.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                responses.append(response)
            }
        }

        return responses.sorted {
            $0.timestamp == $1.timestamp ? $0.id < $1.id : $0.timestamp < $1.timestamp
        }
    }

    static func belongsToWorkspace(_ jsonLines: String, workspacePath: String) -> Bool {
        let expectedWorkspace = standardizedPath(workspacePath)
        for line in jsonLines.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            if object["type"] as? String == "session_meta",
               let payload = object["payload"] as? [String: Any],
               let cwd = payload["cwd"] as? String {
                return standardizedPath(cwd) == expectedWorkspace
            }
            if let cwd = object["cwd"] as? String {
                return standardizedPath(cwd) == expectedWorkspace
            }
        }
        return false
    }

    static func sessionStartedAt(_ jsonLines: String) -> Date? {
        for line in jsonLines.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let timestamp = object["timestamp"] as? String,
                  let date = parseDate(timestamp) else {
                continue
            }
            return date
        }
        return nil
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

    private static func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
            ?? ISO8601DateFormatter().date(from: value)
    }

    private static func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }
}

nonisolated actor AgentTranscriptMonitor: AgentResponseSource {
    private static let maximumTranscriptBytes = 16 * 1024 * 1024

    private struct CachedTranscript {
        let modificationDate: Date
        let size: Int
        let responses: [AgentResponse]
    }

    private let workspacePath: String
    private let modifiedAfter: Date
    private let roots: [URL]
    private var discoveredURLs: [URL] = []
    private var cache: [URL: CachedTranscript] = [:]
    private var nextDiscoveryDate = Date.distantPast

    init(
        workspacePath: String,
        modifiedAfter: Date = Date(),
        roots: [URL]? = nil
    ) {
        self.workspacePath = workspacePath
        self.modifiedAfter = modifiedAfter
        if let roots {
            self.roots = roots
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            self.roots = [
                home.appendingPathComponent(".codex/sessions", isDirectory: true),
                home.appendingPathComponent(".claude/projects", isDirectory: true)
            ]
        }
    }

    func loadResponses() async -> [AgentResponse] {
        if Date() >= nextDiscoveryDate {
            discoveredURLs = transcriptURLs()
            nextDiscoveryDate = Date().addingTimeInterval(2)
            let activeURLs = Set(discoveredURLs)
            cache = cache.filter { activeURLs.contains($0.key) }
        }

        var responses: [AgentResponse] = []

        for url in discoveredURLs {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let modificationDate = attributes[.modificationDate] as? Date,
                  let size = (attributes[.size] as? NSNumber)?.intValue else {
                continue
            }
            if let cached = cache[url],
               cached.modificationDate == modificationDate,
               cached.size == size {
                responses.append(contentsOf: cached.responses)
                continue
            }
            guard let jsonLines = try? String(contentsOf: url, encoding: .utf8),
                  AgentTranscriptParser.belongsToWorkspace(
                    jsonLines,
                    workspacePath: workspacePath
                  ) else {
                continue
            }
            let parsed = AgentTranscriptParser.extractAll(
                from: jsonLines,
                workspacePath: workspacePath,
                sourceID: url.path,
                modifiedAfter: modifiedAfter
            )
            cache[url] = CachedTranscript(
                modificationDate: modificationDate,
                size: size,
                responses: parsed
            )
            responses.append(contentsOf: parsed)
        }

        var unique: [String: AgentResponse] = [:]
        for response in responses {
            unique[response.id] = response
        }
        return unique.values.sorted {
            $0.timestamp == $1.timestamp ? $0.id < $1.id : $0.timestamp < $1.timestamp
        }
    }

    private func transcriptURLs() -> [URL] {
        var urls: [URL] = []
        let keys: Set<URLResourceKey> = [
            .contentModificationDateKey,
            .fileSizeKey,
            .isRegularFileKey
        ]

        for root in roots where FileManager.default.fileExists(atPath: root.path) {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles]
            ) else { continue }

            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                guard let values = try? url.resourceValues(forKeys: keys),
                      values.isRegularFile == true,
                      let date = values.contentModificationDate,
                      date >= modifiedAfter,
                      let size = values.fileSize,
                      size <= Self.maximumTranscriptBytes else {
                    continue
                }
                urls.append(url)
            }
        }
        return urls.sorted { $0.path < $1.path }
    }
}

@MainActor
@Observable
final class AgentResponsesModel {
    private(set) var responses: [AgentResponse] = []
    private(set) var isMonitoring = false
    private(set) var selectedSession: AgentSessionIdentity?

    private let source: any AgentResponseSource
    private var responseIDs: Set<AgentResponseReadIdentity> = []
    private var readResponseIDs: Set<AgentResponseReadIdentity> = []
    private var monitorTask: Task<Void, Never>?

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
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stop() {
        monitorTask?.cancel()
        monitorTask = nil
        isMonitoring = false
    }

    func refresh() async {
        let loaded = await source.loadResponses()
        guard !Task.isCancelled else { return }
        let newResponses = loaded.filter { responseIDs.insert($0.readIdentity).inserted }
        guard !newResponses.isEmpty else { return }
        responses.append(contentsOf: newResponses)
        responses.sort {
            $0.timestamp == $1.timestamp ? $0.id < $1.id : $0.timestamp < $1.timestamp
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
