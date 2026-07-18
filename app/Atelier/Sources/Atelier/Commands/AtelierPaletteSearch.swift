import Foundation

nonisolated struct AtelierFileCandidate: Identifiable, Equatable, Sendable {
    let url: URL
    let relativePath: String

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
}

nonisolated enum AtelierPaletteSearch {
    static let maximumResults = 100

    static func rankFiles(
        _ candidates: [AtelierFileCandidate],
        query: String,
        recentURLs: [URL],
        limit: Int = maximumResults
    ) -> [AtelierPaletteFileMatch] {
        let limit = min(max(0, limit), maximumResults)
        guard limit > 0 else { return [] }

        let candidatesByPath = Dictionary(
            uniqueKeysWithValues: candidates.map { ($0.url.standardizedFileURL.path, $0) }
        )
        let recentRanks = Dictionary(
            uniqueKeysWithValues: recentURLs.prefix(RecentFileHistory.maximumCount).enumerated().map {
                ($0.element.standardizedFileURL.path, RecentFileHistory.maximumCount - $0.offset)
            }
        )
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if normalizedQuery.isEmpty {
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

        return candidates.compactMap { candidate in
            guard let score = score(
                query: normalizedQuery,
                fileName: candidate.fileName.lowercased(),
                relativePath: candidate.relativePath.lowercased()
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
            let lhsPath = lhs.candidate.relativePath.lowercased()
            let rhsPath = rhs.candidate.relativePath.lowercased()
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
        return subsequenceScore(query: normalizedQuery, text: normalizedText)
    }

    static func rankCommands(
        _ descriptors: [AtelierActionDescriptor],
        query: String,
        context: AtelierActionContext
    ) -> [AtelierPaletteCommandMatch] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
            let lhsIndex = descriptors.firstIndex { $0.id == lhs.descriptor.id } ?? 0
            let rhsIndex = descriptors.firstIndex { $0.id == rhs.descriptor.id } ?? 0
            return lhsIndex < rhsIndex
        }
    }

    private static func score(
        query: String,
        fileName: String,
        relativePath: String
    ) -> Int? {
        guard let subsequence = subsequenceScore(query: query, text: relativePath) else {
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

    private static func subsequenceScore(query: String, text: String) -> Int? {
        let queryCharacters = Array(query)
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
