import Foundation
import Testing
@testable import Atelier

@Suite("Atelier palette search")
struct AtelierPaletteSearchTests {
    @Test("File ranking prefers exact names and stable paths")
    func stableRanking() {
        let root = URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        let candidates = [
            candidate(root: root, path: "Sources/AppModel.swift"),
            candidate(root: root, path: "Tests/AppModelTests.swift"),
            candidate(root: root, path: "Other/MyAppModel.swift")
        ]

        let exact = AtelierPaletteSearch.rankFiles(
            candidates,
            query: "AppModel.swift",
            recentURLs: []
        )
        #expect(exact.first?.candidate.relativePath == "Sources/AppModel.swift")

        let tied = AtelierPaletteSearch.rankFiles(
            candidates,
            query: "am",
            recentURLs: []
        )
        #expect(tied.map(\.candidate.relativePath) == [
            "Sources/AppModel.swift",
            "Tests/AppModelTests.swift",
            "Other/MyAppModel.swift"
        ])
    }

    @Test("Recent file history deduplicates and stays bounded")
    func recentHistory() {
        var history = RecentFileHistory()
        for index in 0..<55 {
            history.record(URL(fileURLWithPath: "/tmp/file-\(index).swift"))
        }
        history.record(URL(fileURLWithPath: "/tmp/file-40.swift"))

        #expect(history.urls.count == 50)
        #expect(history.urls.first?.lastPathComponent == "file-40.swift")
        #expect(history.urls.filter { $0.lastPathComponent == "file-40.swift" }.count == 1)
    }

    @Test("Opening the same file keeps one terminal-tab MRU entry")
    @MainActor
    func terminalTabRecentFile() throws {
        let root = temporaryDirectory("palette-tab-mru")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fileURL = root.appendingPathComponent("main.swift")
        try Data("let value = 1\n".utf8).write(to: fileURL)
        let tabs = TerminalTabsModel(workspacePath: root.path)
        defer { tabs.closeAll() }

        tabs.openFile(fileURL)
        tabs.openFile(fileURL)
        tabs.openFile(fileURL)

        #expect(tabs.recentFileURLs == [fileURL.standardizedFileURL])
    }

    @Test("Workspace index skips ignored directories and symlinks")
    func indexFiltering() async throws {
        let root = temporaryDirectory("palette-index")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try write("main", to: root.appendingPathComponent("Sources/main.swift"))
        for name in [".git", ".build", "node_modules", "DerivedData"] {
            try write("ignored", to: root.appendingPathComponent("\(name)/ignored.txt"))
        }
        let outside = temporaryDirectory("palette-outside")
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try write("outside", to: outside.appendingPathComponent("outside.txt"))
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("Linked"),
            withDestinationURL: outside
        )

        let results = try await WorkspaceFileIndex(rootURL: root).candidates(revision: 0)

        #expect(results.map(\.relativePath) == ["Sources/main.swift"])
    }

    @Test("Search result and recent limits are exact")
    func bounds() {
        let root = URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        let candidates = (0..<120).map { index in
            candidate(root: root, path: "Sources/Item\(index).swift")
        }
        let results = AtelierPaletteSearch.rankFiles(
            candidates,
            query: "item",
            recentURLs: []
        )

        #expect(results.count == 100)
    }

    @Test("A stale search cannot replace a newer result")
    @MainActor
    func cancellation() async {
        let root = URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        let index = DelayedFileIndex(
            slow: [candidate(root: root, path: "Slow.swift")],
            fast: [candidate(root: root, path: "Fast.swift")]
        )
        let model = AtelierPaletteModel(fileIndex: index)

        model.showFiles(revision: 0)
        model.updateQuery("slow")
        model.updateFileRevision(1)
        model.updateQuery("fast")
        await model.settleSearch()

        #expect(model.fileResults.map(\.candidate.relativePath) == ["Fast.swift"])
        #expect(!model.isSearching)
    }

    private func candidate(root: URL, path: String) -> AtelierFileCandidate {
        AtelierFileCandidate(
            url: root.appendingPathComponent(path),
            relativePath: path
        )
    }

    private func temporaryDirectory(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("atelier-tests-\(name)-\(UUID().uuidString)", isDirectory: true)
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(text.utf8).write(to: url)
    }
}

private actor DelayedFileIndex: WorkspaceFileIndexing {
    let slow: [AtelierFileCandidate]
    let fast: [AtelierFileCandidate]

    init(slow: [AtelierFileCandidate], fast: [AtelierFileCandidate]) {
        self.slow = slow
        self.fast = fast
    }

    func candidates(revision: Int) async throws -> [AtelierFileCandidate] {
        if revision == 0 {
            try await Task.sleep(nanoseconds: 100_000_000)
            return slow
        }
        return fast
    }
}
