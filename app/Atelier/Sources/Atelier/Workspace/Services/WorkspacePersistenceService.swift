import Foundation

nonisolated enum WorkspacePersistenceError: LocalizedError, Sendable {
    case read(String)
    case decode(String)
    case write(String)

    var errorDescription: String? {
        switch self {
        case .read(let message):
            "Could not read saved workspace: \(message)"
        case .decode(let message):
            "Could not decode saved workspace: \(message)"
        case .write(let message):
            "Could not save workspace: \(message)"
        }
    }
}

actor WorkspacePersistenceService {
    private let fileURL: URL

    init(fileURL: URL = WorkspacePersistenceService.defaultStateURL()) {
        self.fileURL = fileURL
    }

    func load() throws -> WorkspaceState? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw WorkspacePersistenceError.read(error.localizedDescription)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(WorkspaceState.self, from: data)
        } catch {
            throw WorkspacePersistenceError.decode(error.localizedDescription)
        }
    }

    func save(_ workspace: WorkspaceState?) throws {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            guard let workspace else {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    try FileManager.default.removeItem(at: fileURL)
                }
                return
            }

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(workspace).write(to: fileURL, options: .atomic)
        } catch {
            throw WorkspacePersistenceError.write(error.localizedDescription)
        }
    }

    nonisolated static func defaultStateURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Atelier/state.json")
    }
}
