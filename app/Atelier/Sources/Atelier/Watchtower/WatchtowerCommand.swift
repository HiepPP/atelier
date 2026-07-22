import Foundation
import CoreTransferable
import UniformTypeIdentifiers

// A copy-ready /watchtower skill command, shown as a chip in the panel.
nonisolated struct WatchtowerCommand: Identifiable, Sendable, Equatable {
    let id: String
    let label: String
    let command: String
}

extension WatchtowerCommand {
    private static func make(_ label: String) -> WatchtowerCommand {
        WatchtowerCommand(id: label, label: label, command: "/watchtower \(label)")
    }

    // Subcommand chips, matching the Watchtower dashboard command group.
    static let all: [WatchtowerCommand] = [
        make("new"),
        make("implement"),
        make("implement subagents"),
        make("research"),
        make("next"),
        make("verify"),
        make("progress"),
        make("archive"),
    ]
}

// Dedicated drag payload so only Watchtower command drags run in the terminal;
// a stray plain-text drag will not decode into this type.
nonisolated struct WatchtowerCommandDrop: Codable, Sendable, Transferable {
    let command: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}
