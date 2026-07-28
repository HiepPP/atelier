import Foundation
import Observation

nonisolated enum AtelierPaletteMode: Equatable, Sendable {
    case files
    case commands
}

nonisolated enum AtelierPaletteSelection: Equatable, Sendable {
    case file(URL)
    case action(AtelierActionID)
}

@MainActor
@Observable
final class AtelierPaletteModel {
    private(set) var mode = AtelierPaletteMode.files
    private(set) var query = ""
    private(set) var fileResults: [AtelierPaletteFileMatch] = []
    private(set) var commandResults: [AtelierPaletteCommandMatch] = []
    private(set) var selectedID: String?
    private(set) var isSearching = false
    private(set) var isPresented = false

    private let fileIndex: (any WorkspaceFileIndexing)?
    private let workspaceRoot: URL?
    private let recentFiles: @MainActor () -> [URL]
    private var fileRevision = 0
    private var searchGeneration = 0
    private var searchTask: Task<Void, Never>?

    init(
        fileIndex: (any WorkspaceFileIndexing)? = nil,
        workspaceRoot: URL? = nil,
        recentFiles: @escaping @MainActor () -> [URL] = { [] }
    ) {
        self.fileIndex = fileIndex
        self.workspaceRoot = workspaceRoot
        self.recentFiles = recentFiles
    }

    func showFiles(revision: Int) {
        mode = .files
        isPresented = true
        fileRevision = revision
        updateQuery("")
    }

    func showCommands(context: AtelierActionContext) {
        mode = .commands
        isPresented = true
        query = ""
        selectedID = nil
        searchTask?.cancel()
        isSearching = false
        refreshCommands(context: context)
    }

    func updateQuery(_ query: String, actionContext: AtelierActionContext? = nil) {
        self.query = query
        switch mode {
        case .files:
            refreshFiles()
        case .commands:
            if let actionContext { refreshCommands(context: actionContext) }
        }
    }

    func updateFileRevision(_ revision: Int) {
        guard fileRevision != revision else { return }
        fileRevision = revision
        // A closed panel shows no results, so walking the workspace here is pure
        // waste; every filesystem change would re-index the whole root. Record the
        // revision and let `showFiles(revision:)` walk once when the panel opens.
        guard isPresented, mode == .files else { return }
        refreshFiles()
    }

    func moveSelection(by offset: Int) {
        let ids = resultIDs
        guard !ids.isEmpty else {
            selectedID = nil
            return
        }
        let currentIndex = selectedID.flatMap { id in
            ids.firstIndex(of: id)
        } ?? 0
        let nextIndex = min(max(0, currentIndex + offset), ids.count - 1)
        selectedID = ids[nextIndex]
    }

    func select(id: String?) {
        guard let id, resultIDs.contains(id) else { return }
        selectedID = id
    }

    var selection: AtelierPaletteSelection? {
        switch mode {
        case .files:
            guard let url = fileResults.first(where: { $0.id == selectedID })?.candidate.url else {
                return nil
            }
            return .file(url)
        case .commands:
            guard let match = commandResults.first(where: { $0.id == selectedID }),
                  match.isEnabled else {
                return nil
            }
            return .action(match.descriptor.id)
        }
    }

    func refreshCommands(context: AtelierActionContext) {
        guard mode == .commands else { return }
        let priorSelection = selectedID
        commandResults = AtelierPaletteSearch.rankCommands(
            AtelierActionRegistry.actions,
            query: query,
            context: context
        )
        selectedID = if let priorSelection,
                        commandResults.contains(where: { $0.id == priorSelection }) {
            priorSelection
        } else {
            commandResults.first(where: \.isEnabled)?.id ?? commandResults.first?.id
        }
    }

    func settleSearch() async {
        await searchTask?.value
    }

    func stop() {
        searchGeneration &+= 1
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
        isPresented = false
    }

    func dismiss() {
        stop()
        query = ""
    }

    private func refreshFiles() {
        searchGeneration &+= 1
        let generation = searchGeneration
        searchTask?.cancel()
        guard let fileIndex else {
            fileResults = []
            selectedID = nil
            isSearching = false
            return
        }

        let query = query
        let revision = fileRevision
        let recentURLs = recentFiles()
        let workspaceRoot = workspaceRoot
        isSearching = true
        searchTask = Task { [weak self] in
            do {
                let candidates = try await fileIndex.candidates(revision: revision)
                try Task.checkCancellation()
                // Ranking and the external-path filesystem check both run off the main actor.
                let matches = await Task.detached(priority: .userInitiated) {
                    let ranked = AtelierPaletteSearch.rankFiles(
                        candidates,
                        query: query,
                        recentURLs: recentURLs
                    )
                    guard let external = AtelierPaletteSearch.externalFileMatch(
                        query: query,
                        workspaceRoot: workspaceRoot
                    ) else {
                        return ranked
                    }
                    return [external] + ranked.filter { $0.id != external.id }
                }.value
                try Task.checkCancellation()
                guard let self, self.searchGeneration == generation else { return }
                let priorSelection = self.selectedID
                self.fileResults = matches
                self.selectedID = if let priorSelection,
                                     matches.contains(where: { $0.id == priorSelection }) {
                    priorSelection
                } else {
                    matches.first?.id
                }
                self.isSearching = false
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.searchGeneration == generation else { return }
                self.fileResults = []
                self.selectedID = nil
                self.isSearching = false
            }
        }
    }

    private var resultIDs: [String] {
        switch mode {
        case .files:
            fileResults.map(\.id)
        case .commands:
            commandResults.map(\.id)
        }
    }
}
