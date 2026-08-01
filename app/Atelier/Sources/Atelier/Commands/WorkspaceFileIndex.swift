import Foundation

nonisolated protocol WorkspaceFileIndexing: Sendable {
    func candidates(revision: Int) async throws -> [AtelierFileCandidate]
}

actor WorkspaceFileIndex: WorkspaceFileIndexing {
    private static let maximumCandidateCount = 50_000

    private let rootURL: URL
    private var cachedRevision: Int?
    private var cachedCandidates: [AtelierFileCandidate] = []

    init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL.resolvingSymlinksInPath()
    }

    func candidates(revision: Int) throws -> [AtelierFileCandidate] {
        if cachedRevision == revision {
            return cachedCandidates
        }

        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            cachedRevision = revision
            cachedCandidates = []
            return []
        }

        var result: [AtelierFileCandidate] = []
        while let url = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            let values = try? url.resourceValues(forKeys: keys)
            if values?.isSymbolicLink == true {
                if values?.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            if values?.isDirectory == true {
                if IgnoreRules.shouldSkipIndexing(url) { enumerator.skipDescendants() }
                continue
            }
            guard values?.isRegularFile == true,
                  !IgnoreRules.shouldSkipIndexing(url),
                  let relativePath = relativePath(for: url) else {
                continue
            }
            result.append(
                AtelierFileCandidate(url: url.standardizedFileURL, relativePath: relativePath)
            )
            if result.count == Self.maximumCandidateCount { break }
        }

        result.sort { lhs, rhs in
            if lhs.lowercasedRelativePath != rhs.lowercasedRelativePath {
                return lhs.lowercasedRelativePath < rhs.lowercasedRelativePath
            }
            return lhs.relativePath < rhs.relativePath
        }
        cachedRevision = revision
        cachedCandidates = result
        return result
    }

    private lazy var rootComponents = rootURL.pathComponents

    private func relativePath(for url: URL) -> String? {
        let fileComponents = url.standardizedFileURL.pathComponents
        guard fileComponents.starts(with: rootComponents), fileComponents.count > rootComponents.count else {
            return nil
        }
        return fileComponents.dropFirst(rootComponents.count).joined(separator: "/")
    }
}
