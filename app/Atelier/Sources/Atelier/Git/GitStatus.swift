import Foundation

nonisolated enum GitChangeKind: String, Equatable, Sendable {
    case modified
    case added
    case deleted
    case renamed
    case copied
    case untracked
    case conflicted
    case other
}

nonisolated struct GitChange: Identifiable, Equatable, Sendable {
    let path: String
    let originalPath: String?
    let kind: GitChangeKind
    let isStaged: Bool
    let isUnstaged: Bool

    var id: String {
        "\(path)|\(originalPath ?? "")|\(kind.rawValue)"
    }
}

nonisolated struct GitStatus: Equatable, Sendable {
    let changes: [GitChange]
    let ignoredPaths: Set<String>
    // Partitions are read several times per render; compute them once.
    let staged: [GitChange]
    let unstaged: [GitChange]
    let untracked: [GitChange]

    init(changes: [GitChange], ignoredPaths: Set<String> = []) {
        self.changes = changes
        self.ignoredPaths = ignoredPaths
        staged = changes.filter(\.isStaged)
        unstaged = changes.filter { $0.isUnstaged && $0.kind != .untracked }
        untracked = changes.filter { $0.kind == .untracked }
    }

    static func parse(_ data: Data) -> GitStatus {
        let records = data.split(separator: 0, omittingEmptySubsequences: true)
        var changes: [GitChange] = []
        var ignoredPaths = Set<String>()
        var index = 0

        while index < records.count {
            let record = String(decoding: records[index], as: UTF8.self)

            if record.hasPrefix("? ") {
                changes.append(GitChange(
                    path: String(record.dropFirst(2)),
                    originalPath: nil,
                    kind: .untracked,
                    isStaged: false,
                    isUnstaged: true
                ))
            } else if record.hasPrefix("! ") {
                ignoredPaths.insert(String(record.dropFirst(2)))
            } else if record.hasPrefix("1 "), let change = parseOrdinary(record) {
                changes.append(change)
            } else if record.hasPrefix("2 ") {
                let originalPath = index + 1 < records.count
                    ? String(decoding: records[index + 1], as: UTF8.self)
                    : nil
                if let change = parseRenamed(record, originalPath: originalPath) {
                    changes.append(change)
                }
                index += 1
            } else if record.hasPrefix("u "), let change = parseUnmerged(record) {
                changes.append(change)
            }

            index += 1
        }

        return GitStatus(
            changes: changes.sorted { $0.path < $1.path },
            ignoredPaths: ignoredPaths
        )
    }

    private static func parseOrdinary(_ record: String) -> GitChange? {
        let fields = record.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: true)
        guard fields.count == 9 else { return nil }
        let xy = String(fields[1])
        return GitChange(
            path: String(fields[8]),
            originalPath: nil,
            kind: kind(for: xy),
            isStaged: staged(xy),
            isUnstaged: unstaged(xy)
        )
    }

    private static func parseRenamed(_ record: String, originalPath: String?) -> GitChange? {
        let fields = record.split(separator: " ", maxSplits: 9, omittingEmptySubsequences: true)
        guard fields.count == 10 else { return nil }
        let xy = String(fields[1])
        let score = fields[8].first
        return GitChange(
            path: String(fields[9]),
            originalPath: originalPath,
            kind: score == "C" ? .copied : .renamed,
            isStaged: staged(xy),
            isUnstaged: unstaged(xy)
        )
    }

    private static func parseUnmerged(_ record: String) -> GitChange? {
        let fields = record.split(separator: " ", maxSplits: 10, omittingEmptySubsequences: true)
        guard fields.count == 11 else { return nil }
        return GitChange(
            path: String(fields[10]),
            originalPath: nil,
            kind: .conflicted,
            isStaged: true,
            isUnstaged: true
        )
    }

    private static func staged(_ xy: String) -> Bool {
        xy.first.map { $0 != "." } ?? false
    }

    private static func unstaged(_ xy: String) -> Bool {
        xy.dropFirst().first.map { $0 != "." } ?? false
    }

    private static func kind(for xy: String) -> GitChangeKind {
        let codes = Set(xy.filter { $0 != "." })
        if codes.contains("U") { return .conflicted }
        if codes.contains("R") { return .renamed }
        if codes.contains("C") { return .copied }
        if codes.contains("D") { return .deleted }
        if codes.contains("A") { return .added }
        if codes.contains("M") || codes.contains("T") { return .modified }
        return .other
    }
}
