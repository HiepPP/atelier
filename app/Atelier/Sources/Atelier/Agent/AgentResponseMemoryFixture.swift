#if DEBUG
import SwiftUI

nonisolated enum AgentResponseMemoryFixture {
    static let totalByteCount = 5_120
    static let tableRowCount = 22

    static let responses: [AgentResponse] = [
        response(index: 1, rowCount: 8, byteCount: 1_707),
        response(index: 2, rowCount: 7, byteCount: 1_707),
        response(index: 3, rowCount: 7, byteCount: 1_706)
    ]

    static func textSelectionEnabled(arguments: [String]) -> Bool? {
        let prefix = "--response-memory-fixture="
        guard let argument = arguments.first(where: { $0.hasPrefix(prefix) }) else {
            return nil
        }
        return switch argument.dropFirst(prefix.count) {
        case "selection-enabled": true
        case "selection-disabled": false
        default: nil
        }
    }

    static func scrollCycleCount(arguments: [String]) -> Int {
        let prefix = "--response-memory-profile-scrolls="
        guard let argument = arguments.first(where: { $0.hasPrefix(prefix) }),
              let count = Int(argument.dropFirst(prefix.count)) else { return 0 }
        return max(0, count)
    }

    private static func response(
        index: Int,
        rowCount: Int,
        byteCount: Int
    ) -> AgentResponse {
        AgentResponse(
            id: "memory-fixture-\(index)",
            provider: .codex,
            sessionID: "memory-fixture",
            timestamp: Date(timeIntervalSince1970: TimeInterval(index)),
            markdown: markdown(index: index, rowCount: rowCount, byteCount: byteCount)
        )
    }

    private static func markdown(
        index: Int,
        rowCount: Int,
        byteCount: Int
    ) -> String {
        var lines = [
            "# Response \(index)",
            "",
            "Deterministic response-preview memory fixture.",
            "",
            "| Item | State | Detail | Owner |",
            "| --- | --- | --- | --- |"
        ]
        for row in 1...rowCount {
            lines.append("| \(row) | Ready | Stable fixture row \(row) | Atelier |")
        }
        lines.append(contentsOf: [
            "",
            "## Notes",
            "",
            "- No Mermaid content.",
            "- Four columns exercise nested horizontal scrolling.",
            "- Padding keeps payload size deterministic.",
            "",
            "Padding: "
        ])
        let base = lines.joined(separator: "\n")
        precondition(base.utf8.count <= byteCount)
        return base + String(repeating: "x", count: byteCount - base.utf8.count)
    }
}

nonisolated private struct AgentResponseMemoryFixtureSource: AgentResponseSource {
    let responses: [AgentResponse]

    func loadResponses() async -> [AgentResponse] {
        responses
    }
}

struct AgentResponseMemoryFixtureView: View {
    @State private var model: AgentResponsesModel
    let textSelectionEnabled: Bool
    let profileScrollCycles: Int

    init(textSelectionEnabled: Bool, profileScrollCycles: Int) {
        self.textSelectionEnabled = textSelectionEnabled
        self.profileScrollCycles = profileScrollCycles
        _model = State(initialValue: AgentResponsesModel(
            source: AgentResponseMemoryFixtureSource(
                responses: AgentResponseMemoryFixture.responses
            )
        ))
    }

    var body: some View {
        AgentResponsesView(
            model: model,
            onClose: {},
            textSelectionEnabled: textSelectionEnabled,
            profileScrollCycles: profileScrollCycles
        )
        .frame(width: 448, height: 520)
        .task {
            await model.refresh()
        }
    }
}
#endif
