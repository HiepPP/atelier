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
    typealias LoadHook = @Sendable () async -> Void
    typealias SaveHook = @Sendable (UInt64, WorkspaceCatalogState?) async -> Void

    private let fileURL: URL
    private let beforeLoad: LoadHook
    private let beforeSave: SaveHook
    private var nextSaveRevision: UInt64 = 0
    private var latestRequestedSaveRevision: UInt64 = 0

    init(
        fileURL: URL = WorkspacePersistenceService.defaultStateURL(),
        beforeLoad: @escaping LoadHook = {},
        beforeSave: @escaping SaveHook = { _, _ in }
    ) {
        self.fileURL = fileURL
        self.beforeLoad = beforeLoad
        self.beforeSave = beforeSave
    }

    func load() async throws -> WorkspaceCatalogState? {
        await beforeLoad()
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
            if let catalog = try? decoder.decode(WorkspaceCatalogState.self, from: data) {
                return catalog
            }
            let legacy = try decoder.decode(WorkspaceState.self, from: data)
            return WorkspaceCatalogState(
                workspaces: [legacy],
                selectedWorkspaceID: legacy.id
            )
        } catch {
            throw WorkspacePersistenceError.decode(error.localizedDescription)
        }
    }

    func save(_ catalog: WorkspaceCatalogState?) async throws {
        nextSaveRevision &+= 1
        let revision = nextSaveRevision
        latestRequestedSaveRevision = revision
        await beforeSave(revision, catalog)
        guard revision == latestRequestedSaveRevision else { return }

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            guard let catalog else {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    try FileManager.default.removeItem(at: fileURL)
                }
                return
            }

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(catalog).write(to: fileURL, options: .atomic)
        } catch {
            throw WorkspacePersistenceError.write(error.localizedDescription)
        }
    }

    nonisolated static func defaultStateURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Atelier/state.json")
    }
}
