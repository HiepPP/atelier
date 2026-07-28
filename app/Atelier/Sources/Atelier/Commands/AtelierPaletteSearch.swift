import Foundation

nonisolated struct AtelierFileCandidate: Identifiable, Equatable, Sendable {
    let url: URL
    let relativePath: String
    // Precomputed at index time so per-keystroke ranking never lowercases.
    let lowercasedFileName: String
    let lowercasedRelativePath: String

    init(url: URL, relativePath: String) {
        self.url = url
        self.relativePath = relativePath
        lowercasedFileName = url.lastPathComponent.lowercased()
        lowercasedRelativePath = relativePath.lowercased()
    }

    var id: String { url.path }
    var fileName: String { url.lastPathComponent }
}

nonisolated struct AtelierPaletteFileMatch: Identifiable, Equatable, Sendable {
    let candidate: AtelierFileCandidate
    let score: Int

    var id: String { candidate.id }
}

nonisolated struct AtelierPaletteCommandMatch: Identifiable, Equatable, Sendable {
    let descriptor: AtelierActionDescriptor
    let title: String
    let isEnabled: Bool
    let score: Int

    var id: String { descriptor.id.rawValue }
}

nonisolated struct RecentFileHistory: Equatable, Sendable {
    static let maximumCount = 50

    private(set) var urls: [URL] = []

    mutating func record(_ url: URL) {
        let standardizedURL = url.standardizedFileURL
        urls.removeAll { $0 == standardizedURL }
        urls.insert(standardizedURL, at: 0)
        if urls.count > Self.maximumCount {
            urls.removeLast(urls.count - Self.maximumCount)
        }
    }

    mutating func removeAll() {
        urls.removeAll(keepingCapacity: false)
    }

    mutating func removeItem(at url: URL) {
        urls.removeAll { FileTreePathPolicy.contains($0, within: url) }
    }
}

nonisolated enum AtelierPaletteSearch {
    static let maximumResults = 100
    // Ranked above the exact-file-name tier so an explicit path always leads.
    static let externalPathScore = 50_000

    /// Resolves a query that names an absolute filesystem path to a file outside the workspace.
    /// Returns nil unless the query starts with `/` or `~/` and resolves to an existing regular
    /// file outside `workspaceRoot`; indexed results stay the single source for in-workspace files.
    static func externalFileURL(query: String, workspaceRoot: URL?) -> URL? {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.hasPrefix("/") || trimmedQuery.hasPrefix("~/") else { return nil }

        let expandedPath = (trimmedQuery as NSString).expandingTildeInPath
        guard !expandedPath.isEmpty, expandedPath.hasPrefix("/") else { return nil }

        let url = URL(fileURLWithPath: expandedPath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return nil
        }
        if let workspaceRoot {
            let root = workspaceRoot.standardizedFileURL.resolvingSymlinksInPath()
            guard !FileTreePathPolicy.contains(url, within: root) else { return nil }
        }
        return url
    }

    /// Wraps an external path result so it can lead `fileResults` alongside ranked index matches.
    /// The candidate carries the absolute path so the panel renders it in place of a relative path.
    static func externalFileMatch(query: String, workspaceRoot: URL?) -> AtelierPaletteFileMatch? {
        guard let url = externalFileURL(query: query, workspaceRoot: workspaceRoot) else {
            return nil
        }
        return AtelierPaletteFileMatch(
            candidate: AtelierFileCandidate(url: url, relativePath: url.path),
            score: externalPathScore
        )
    }

    static func rankFiles(
        _ candidates: [AtelierFileCandidate],
        query: String,
        recentURLs: [URL],
        limit: Int = maximumResults
    ) -> [AtelierPaletteFileMatch] {
        let limit = min(max(0, limit), maximumResults)
        guard limit > 0 else { return [] }

        let recentRanks = Dictionary(
            uniqueKeysWithValues: recentURLs.prefix(RecentFileHistory.maximumCount).enumerated().map {
                ($0.element.standardizedFileURL.path, RecentFileHistory.maximumCount - $0.offset)
            }
        )
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if normalizedQuery.isEmpty {
            // Only the empty-query branch needs the path lookup; building it
            // for every keystroke wasted O(candidates) per key.
            let candidatesByPath = Dictionary(
                uniqueKeysWithValues: candidates.map { ($0.url.standardizedFileURL.path, $0) }
            )
            return recentURLs.compactMap { url in
                guard let candidate = candidatesByPath[url.standardizedFileURL.path] else {
                    return nil
                }
                return AtelierPaletteFileMatch(
                    candidate: candidate,
                    score: recentRanks[candidate.url.path] ?? 0
                )
            }
            .prefix(limit)
            .map(\.self)
        }

        let queryCharacters = Array(normalizedQuery)
        return candidates.compactMap { candidate in
            guard let score = score(
                queryCharacters: queryCharacters,
                query: normalizedQuery,
                fileName: candidate.lowercasedFileName,
                relativePath: candidate.lowercasedRelativePath
            ) else {
                return nil
            }
            return AtelierPaletteFileMatch(
                candidate: candidate,
                score: score + (recentRanks[candidate.url.path] ?? 0)
            )
        }
        .sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            let lhsPath = lhs.candidate.lowercasedRelativePath
            let rhsPath = rhs.candidate.lowercasedRelativePath
            if lhsPath != rhsPath { return lhsPath < rhsPath }
            return lhs.candidate.relativePath < rhs.candidate.relativePath
        }
        .prefix(limit)
        .map(\.self)
    }

    static func score(query: String, text: String) -> Int? {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedText = text.lowercased()
        guard !normalizedQuery.isEmpty else { return 0 }
        return subsequenceScore(queryCharacters: Array(normalizedQuery), text: normalizedText)
    }

    static func rankCommands(
        _ descriptors: [AtelierActionDescriptor],
        query: String,
        context: AtelierActionContext
    ) -> [AtelierPaletteCommandMatch] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let indexByID = Dictionary(
            uniqueKeysWithValues: descriptors.enumerated().map { ($0.element.id, $0.offset) }
        )
        return descriptors.enumerated().compactMap { index, descriptor in
            let title = AtelierActionRegistry.title(for: descriptor.id, context: context)
            let resultScore: Int
            if normalizedQuery.isEmpty {
                resultScore = descriptors.count - index
            } else {
                let searchableText = "\(title) \(descriptor.category)"
                guard let fuzzyScore = score(query: normalizedQuery, text: searchableText) else {
                    return nil
                }
                resultScore = fuzzyScore
            }
            return AtelierPaletteCommandMatch(
                descriptor: descriptor,
                title: title,
                isEnabled: AtelierActionRegistry.isEnabled(descriptor.id, context: context),
                score: resultScore
            )
        }
        .sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            let lhsIndex = indexByID[lhs.descriptor.id] ?? 0
            let rhsIndex = indexByID[rhs.descriptor.id] ?? 0
            return lhsIndex < rhsIndex
        }
    }

    private static func score(
        queryCharacters: [Character],
        query: String,
        fileName: String,
        relativePath: String
    ) -> Int? {
        guard let subsequence = subsequenceScore(
            queryCharacters: queryCharacters,
            text: relativePath
        ) else {
            return nil
        }
        if fileName == query {
            return 40_000 + subsequence
        }
        if fileName.hasPrefix(query) {
            return 30_000 + subsequence
        }
        if relativePath.split(separator: "/").contains(where: { $0.hasPrefix(query) }) {
            return 20_000 + subsequence
        }
        return 10_000 + subsequence
    }

    private static func subsequenceScore(queryCharacters: [Character], text: String) -> Int? {
        let textCharacters = Array(text)
        var cursor = 0
        var previousIndex: Int?
        var consecutive = 0
        var boundaries = 0
        var gaps = 0

        for queryCharacter in queryCharacters {
            guard let matchIndex = textCharacters[cursor...].firstIndex(of: queryCharacter) else {
                return nil
            }
            if let previousIndex {
                if matchIndex == previousIndex + 1 {
                    consecutive += 1
                } else {
                    gaps += matchIndex - previousIndex - 1
                }
            }
            if matchIndex == 0 || "/-_. ".contains(textCharacters[matchIndex - 1]) {
                boundaries += 1
            }
            previousIndex = matchIndex
            cursor = matchIndex + 1
        }

        return (consecutive * 40) + (boundaries * 20) - gaps - textCharacters.count
    }
}
