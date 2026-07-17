import Foundation

nonisolated enum MermaidMarkdownParser {
    private static let maximumCaptureSize = 512 * 1024

    static func extractAll(from markdown: String) -> [String] {
        guard markdown.utf8.count <= maximumCaptureSize else { return [] }

        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var sources: [String] = []
        var capturedLines: [String] = []
        var isCapturing = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if isCapturing {
                if trimmed == "```" || trimmed == "~~~" {
                    let source = capturedLines.joined(separator: "\n")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !source.isEmpty {
                        sources.append(source)
                    }
                    capturedLines.removeAll(keepingCapacity: true)
                    isCapturing = false
                } else {
                    capturedLines.append(line)
                }
                continue
            }

            let lowered = trimmed.lowercased()
            if lowered == "```mermaid" || lowered == "~~~mermaid" {
                isCapturing = true
            }
        }

        return sources
    }

    static func extractLatest(from markdown: String) -> String? {
        extractAll(from: markdown).last
    }
}

nonisolated enum MermaidTerminalSourceLocator {
    static func ranges(in rows: [String], sources: [String]) -> [Range<Int>] {
        var upperBound = rows.count
        var matches: [Range<Int>] = []

        for source in sources.reversed() {
            guard let range = range(
                in: rows,
                source: source,
                upperBound: upperBound
            ) else { continue }
            matches.append(range)
            upperBound = range.lowerBound
        }

        return matches.reversed()
    }

    private static func range(
        in rows: [String],
        source: String,
        upperBound: Int
    ) -> Range<Int>? {
        let sourceLines = source.components(separatedBy: .newlines)
            .map(canonicalText)
            .filter { !$0.isEmpty }
        guard let declaration = sourceLines.first else { return nil }
        let canonicalSource = sourceLines.joined(separator: " ")
        let searchEnd = min(upperBound, rows.count)

        for start in (0..<searchEnd).reversed() {
            let firstRow = canonicalText(rows[start])
            guard firstRow.contains(declaration) else { continue }

            var renderedSource = ""
            let maximumEnd = min(searchEnd, start + max(sourceLines.count * 4, 12))
            for end in start..<maximumEnd {
                let row = canonicalText(rows[end])
                if !row.isEmpty {
                    renderedSource += renderedSource.isEmpty ? row : " \(row)"
                }
                if renderedSource.contains(canonicalSource) {
                    return start..<(end + 1)
                }
            }
        }

        return nil
    }

    private static func canonicalText(_ value: String) -> String {
        let words = value.lowercased().split { character in
            !character.isLetter && !character.isNumber
        }
        return words.joined(separator: " ")
    }
}

nonisolated struct AgentMermaidDiagram: Equatable, Sendable {
    let id: String
    let source: String
}

nonisolated enum AgentTranscriptMermaidParser {
    static func extractLatest(
        from jsonLines: String,
        workspacePath: String,
        modifiedAfter: Date
    ) -> String? {
        extractAll(
            from: jsonLines,
            workspacePath: workspacePath,
            modifiedAfter: modifiedAfter
        ).last?.source
    }

    static func extractAll(
        from jsonLines: String,
        workspacePath: String,
        modifiedAfter: Date
    ) -> [AgentMermaidDiagram] {
        let expectedWorkspace = standardizedPath(workspacePath)
        var codexWorkspace: String?
        var diagrams: [(date: Date, order: Int, diagram: AgentMermaidDiagram)] = []
        var recordOrder = 0

        for line in jsonLines.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            if object["type"] as? String == "session_meta",
               let payload = object["payload"] as? [String: Any],
               let cwd = payload["cwd"] as? String {
                codexWorkspace = standardizedPath(cwd)
                continue
            }

            let text: String?
            if codexWorkspace == expectedWorkspace {
                text = codexAssistantText(from: object)
            } else if let cwd = object["cwd"] as? String,
                      standardizedPath(cwd) == expectedWorkspace {
                text = claudeAssistantText(from: object)
            } else {
                text = nil
            }

            guard let text,
                  let timestamp = object["timestamp"] as? String,
                  let date = parseDate(timestamp),
                  date >= modifiedAfter else {
                continue
            }
            for (index, source) in MermaidMarkdownParser.extractAll(from: text).enumerated() {
                diagrams.append((
                    date,
                    recordOrder,
                    AgentMermaidDiagram(
                        id: "\(timestamp)#\(recordOrder)#\(index)",
                        source: source
                    )
                ))
            }
            recordOrder += 1
        }

        return diagrams.sorted {
            $0.date == $1.date ? $0.order < $1.order : $0.date < $1.date
        }.map(\.diagram)
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

nonisolated actor AgentTranscriptMermaidMonitor {
    private let workspacePath: String
    private let modifiedAfter: Date
    private var transcriptURL: URL?
    private var nextDiscoveryDate = Date.distantPast

    init(workspacePath: String, modifiedAfter: Date = Date()) {
        self.workspacePath = workspacePath
        self.modifiedAfter = modifiedAfter
    }

    func diagrams() -> [AgentMermaidDiagram] {
        if transcriptURL == nil, Date() >= nextDiscoveryDate {
            transcriptURL = discoverTranscript()
            nextDiscoveryDate = Date().addingTimeInterval(1)
        }
        guard let transcriptURL,
              let jsonLines = try? String(contentsOf: transcriptURL, encoding: .utf8) else {
            return []
        }
        return AgentTranscriptMermaidParser.extractAll(
            from: jsonLines,
            workspacePath: workspacePath,
            modifiedAfter: modifiedAfter
        ).map {
            AgentMermaidDiagram(
                id: "\(transcriptURL.lastPathComponent):\($0.id)",
                source: $0.source
            )
        }
    }

    private func discoverTranscript() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = [
            home.appendingPathComponent(".codex/sessions", isDirectory: true),
            home.appendingPathComponent(".claude/projects", isDirectory: true)
        ]
        var candidates: [(url: URL, date: Date)] = []

        for root in roots where FileManager.default.fileExists(atPath: root.path) {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                guard let values = try? url.resourceValues(
                    forKeys: [.contentModificationDateKey, .isRegularFileKey]
                ), values.isRegularFile == true,
                let date = values.contentModificationDate,
                date >= modifiedAfter else { continue }
                candidates.append((url, date))
            }
        }

        for candidate in candidates.sorted(by: { $0.date > $1.date }) {
            guard let header = readPrefix(of: candidate.url),
                  let sessionStart = AgentTranscriptMermaidParser.sessionStartedAt(header),
                  sessionStart >= modifiedAfter,
                  AgentTranscriptMermaidParser.belongsToWorkspace(
                    header,
                    workspacePath: workspacePath
                  ) else { continue }
            return candidate.url
        }
        return nil
    }

    private func readPrefix(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let data = try? handle.read(upToCount: 128 * 1024)
        return data.flatMap { String(data: $0, encoding: .utf8) }
    }
}
