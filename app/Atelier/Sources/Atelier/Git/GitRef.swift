import Foundation

nonisolated enum GitRefKind: String, Equatable, Sendable, CaseIterable {
    case localBranch
    case remoteBranch
    case tag

    var sectionTitle: String {
        switch self {
        case .localBranch: "branches"
        case .remoteBranch: "remote branches"
        case .tag: "tags"
        }
    }

    var systemImage: String {
        switch self {
        case .localBranch: "arrow.triangle.branch"
        case .remoteBranch: "cloud"
        case .tag: "tag"
        }
    }
}

nonisolated struct GitRef: Identifiable, Equatable, Sendable {
    let name: String
    let kind: GitRefKind
    let shortHash: String
    let author: String
    let subject: String
    let date: Date
    let isCurrent: Bool

    var id: String { "\(kind.rawValue)|\(name)" }

    /// Local branch a remote ref checks out as: `origin/feature/x` -> `feature/x`.
    /// Only meaningful for `.remoteBranch`.
    var localTrackingName: String {
        guard kind == .remoteBranch else { return name }
        guard let slash = name.firstIndex(of: "/") else { return name }
        return String(name[name.index(after: slash)...])
    }

    /// One line of searchable text, precomputed at parse time so the filter
    /// never lowercases or concatenates per keystroke per candidate.
    var searchText: String {
        "\(name) \(author) \(subject)".lowercased()
    }
}

/// Parses `git for-each-ref` records. Annotated tags point at a tag object, so
/// every commit field has a dereferenced `*` twin; the first non-empty of the
/// pair wins. Anything missing its required fields is dropped rather than shown
/// as a blank row.
nonisolated enum GitRefParser {
    static let format = [
        "%(refname)",
        "%(refname:short)",
        "%(objectname:short)",
        "%(*objectname:short)",
        "%(authorname)",
        "%(*authorname)",
        "%(committerdate:unix)",
        "%(*committerdate:unix)",
        "%(contents:subject)",
        "%(*contents:subject)",
        "%(HEAD)"
    ].joined(separator: "\u{001F}") + "\u{001E}"

    private static let recordSeparator: Character = "\u{001E}"
    private static let fieldSeparator: Character = "\u{001F}"

    static func parse(_ data: Data) -> [GitRef] {
        String(decoding: data, as: UTF8.self)
            .split(separator: recordSeparator, omittingEmptySubsequences: true)
            .compactMap(parseRecord)
    }

    private static func parseRecord(_ record: Substring) -> GitRef? {
        let fields = record
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: fieldSeparator, maxSplits: 10, omittingEmptySubsequences: false)
        guard fields.count == 11 else { return nil }

        let fullName = String(fields[0])
        guard let kind = kind(forFullName: fullName) else { return nil }

        let name = String(fields[1])
        // `origin/HEAD` is a symbolic pointer at another row in the same list.
        guard !name.isEmpty, !name.hasSuffix("/HEAD") else { return nil }

        // Every row describes the commit it points at. An annotated tag points
        // at a tag object, so its own hash, tagger, and message must lose to
        // the dereferenced commit's.
        let shortHash = commitField(dereferenced: fields[3], direct: fields[2])
        guard !shortHash.isEmpty else { return nil }

        let timestamp = Double(commitField(dereferenced: fields[7], direct: fields[6])) ?? 0

        return GitRef(
            name: name,
            kind: kind,
            shortHash: shortHash,
            author: commitField(dereferenced: fields[5], direct: fields[4]),
            subject: commitField(dereferenced: fields[9], direct: fields[8]),
            date: Date(timeIntervalSince1970: timestamp),
            isCurrent: fields[10] == "*"
        )
    }

    private static func kind(forFullName fullName: String) -> GitRefKind? {
        if fullName.hasPrefix("refs/heads/") { return .localBranch }
        if fullName.hasPrefix("refs/remotes/") { return .remoteBranch }
        if fullName.hasPrefix("refs/tags/") { return .tag }
        return nil
    }

    private static func commitField(dereferenced: Substring, direct: Substring) -> String {
        let trimmed = dereferenced.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return direct.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

nonisolated enum GitRefFilter {
    /// Ranked purely by section order and recency; the query only narrows the
    /// set. Branch pickers are small, so scoring adds cost without value.
    static func apply(_ query: String, to refs: [GitRef]) -> [GitRef] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return refs }
        return refs.filter { $0.searchText.contains(needle) }
    }
}

nonisolated enum GitRelativeTime {
    static func label(for date: Date, now: Date = .now) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "just now" }
        if seconds < 3_600 { return "\(seconds / 60) minutes ago" }
        if seconds < 86_400 { return "\(seconds / 3_600) hours ago" }
        return "\(seconds / 86_400) days ago"
    }
}
