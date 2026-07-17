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
        AgentTranscriptParser.extractAll(
            from: jsonLines,
            workspacePath: workspacePath,
            sourceID: "inline",
            modifiedAfter: modifiedAfter
        ).flatMap { response in
            MermaidMarkdownParser.extractAll(from: response.markdown).enumerated().map { index, source in
                AgentMermaidDiagram(id: "\(response.id)#\(index)", source: source)
            }
        }
    }

    static func belongsToWorkspace(_ jsonLines: String, workspacePath: String) -> Bool {
        AgentTranscriptParser.belongsToWorkspace(jsonLines, workspacePath: workspacePath)
    }

    static func sessionStartedAt(_ jsonLines: String) -> Date? {
        AgentTranscriptParser.sessionStartedAt(jsonLines)
    }
}
