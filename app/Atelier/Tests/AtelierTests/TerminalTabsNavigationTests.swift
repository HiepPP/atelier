import Foundation
import Testing
@testable import Atelier

@Suite("Terminal tab navigation")
@MainActor
struct TerminalTabsNavigationTests {
    @Test("History moves backward and forward without recursive entries")
    func historyTraversal() {
        var history = FileNavigationHistory()
        let a = target("A.swift")
        let b = target("B.swift")
        let c = target("C.swift")

        history.record(a)
        history.record(b)
        history.record(c)

        #expect(history.goBack() == b)
        #expect(history.goBack() == a)
        #expect(!history.canGoBack)
        #expect(history.goForward() == b)
        #expect(history.goForward() == c)
        #expect(!history.canGoForward)
    }

    @Test("New navigation clears forward history and stacks stay bounded")
    func historyBranchAndBounds() {
        var history = FileNavigationHistory()
        history.record(target("A.swift"))
        history.record(target("B.swift"))
        history.record(target("C.swift"))
        #expect(history.goBack() == target("B.swift"))

        history.record(target("D.swift"))

        #expect(!history.canGoForward)
        for index in 0...FileNavigationHistory.limit {
            history.record(target("Bound-\(index).swift"))
        }
        #expect(history.backward.count == FileNavigationHistory.limit)
    }

    @Test("Closed history accepts permanent files only in last-closed-first order")
    func closedHistory() {
        var history = FileNavigationHistory()
        let a = target("A.swift")
        let b = target("B.swift")
        history.recordClosed(a)
        history.recordClosed(
            FileNavigationTarget(url: URL(fileURLWithPath: "/tmp/Preview.swift"), disposition: .preview)
        )
        history.recordClosed(b)

        #expect(history.reopenClosed() == b)
        #expect(history.reopenClosed() == a)
        #expect(!history.canReopenClosed)
    }

    @Test("Terminal tab model branches history and reopens permanent files")
    func modelHistoryIntegration() throws {
        let fixture = try Fixture(names: ["A.swift", "B.swift", "C.swift", "D.swift"])
        defer { fixture.remove() }
        let tabs = TerminalTabsModel(workspacePath: fixture.root.path)
        defer { tabs.closeAll() }

        tabs.openFile(fixture.url("A.swift"))
        tabs.openFile(fixture.url("B.swift"))
        tabs.openFile(fixture.url("C.swift"))
        tabs.navigateBack()
        #expect(tabs.selectedFileURL == fixture.url("B.swift").standardizedFileURL)
        tabs.navigateForward()
        #expect(tabs.selectedFileURL == fixture.url("C.swift").standardizedFileURL)

        tabs.navigateBack()
        tabs.openFile(fixture.url("D.swift"))
        #expect(!tabs.canNavigateForward)

        tabs.closeSelectedTab()
        #expect(tabs.canReopenClosedTab)
        tabs.reopenClosedTab()
        #expect(tabs.selectedFileURL == fixture.url("D.swift").standardizedFileURL)
        #expect(tabs.selectedFileDisposition == .permanent)
    }

    @Test("Preview closure and workspace cleanup do not leave reopen state")
    func previewClosureAndCleanup() throws {
        let fixture = try Fixture(names: ["A.swift"])
        defer { fixture.remove() }
        let tabs = TerminalTabsModel(workspacePath: fixture.root.path)

        tabs.previewFile(fixture.url("A.swift"))
        tabs.closeSelectedTab()
        #expect(!tabs.canReopenClosedTab)

        tabs.openFile(fixture.url("A.swift"))
        tabs.closeSelectedTab()
        #expect(tabs.canReopenClosedTab)
        tabs.closeAll()

        #expect(!tabs.canNavigateBack)
        #expect(!tabs.canNavigateForward)
        #expect(!tabs.canReopenClosedTab)
    }

    @Test("Navigation availability follows model history and closed tabs")
    func actionAvailabilityState() throws {
        let fixture = try Fixture(names: ["A.swift", "B.swift"])
        defer { fixture.remove() }
        let tabs = TerminalTabsModel(workspacePath: fixture.root.path)
        defer { tabs.closeAll() }

        #expect(!tabs.canNavigateBack)
        #expect(!tabs.canNavigateForward)
        #expect(!tabs.canReopenClosedTab)

        tabs.openFile(fixture.url("A.swift"))
        tabs.openFile(fixture.url("B.swift"))
        #expect(tabs.canNavigateBack)

        tabs.navigateBack()
        #expect(tabs.canNavigateForward)

        tabs.closeSelectedTab()
        #expect(tabs.canReopenClosedTab)
    }

    @Test("Preview replacement stays singular and does not update recent files")
    func previewReplacement() throws {
        let fixture = try Fixture(names: ["A.swift", "B.swift", "C.swift"])
        defer { fixture.remove() }
        let tabs = TerminalTabsModel(workspacePath: fixture.root.path)
        defer { tabs.closeAll() }

        tabs.previewFile(fixture.url("A.swift"))
        let firstPreviewID = tabs.selectedID
        tabs.previewFile(fixture.url("B.swift"))

        #expect(tabs.fileTabCount == 1)
        #expect(tabs.previewFileTabCount == 1)
        #expect(tabs.previewFileURL == fixture.url("B.swift").standardizedFileURL)
        #expect(tabs.selectedID != firstPreviewID)
        #expect(tabs.recentFileURLs.isEmpty)

        tabs.previewFile(fixture.url("C.swift"))

        #expect(tabs.fileTabCount == 1)
        #expect(tabs.previewFileURL == fixture.url("C.swift").standardizedFileURL)
        #expect(tabs.recentFileURLs.isEmpty)
    }

    @Test("Permanent open promotes preview without changing tab identity")
    func permanentOpenPromotesPreview() throws {
        let fixture = try Fixture(names: ["A.swift", "B.swift"])
        defer { fixture.remove() }
        let tabs = TerminalTabsModel(workspacePath: fixture.root.path)
        defer { tabs.closeAll() }

        tabs.previewFile(fixture.url("A.swift"))
        let previewID = tabs.selectedID
        tabs.openFile(fixture.url("A.swift"))

        #expect(tabs.selectedID == previewID)
        #expect(tabs.selectedFileDisposition == .permanent)
        #expect(tabs.previewFileTabCount == 0)
        #expect(tabs.recentFileURLs == [fixture.url("A.swift").standardizedFileURL])

        tabs.previewFile(fixture.url("B.swift"))
        tabs.previewFile(fixture.url("A.swift"))

        #expect(tabs.fileTabCount == 2)
        #expect(tabs.previewFileURL == fixture.url("B.swift").standardizedFileURL)
        #expect(tabs.selectedFileURL == fixture.url("A.swift").standardizedFileURL)
        #expect(tabs.selectedFileDisposition == .permanent)
    }

    @Test("Explicit promotion records one recent file entry")
    func explicitPromotion() throws {
        let fixture = try Fixture(names: ["A.swift"])
        defer { fixture.remove() }
        let tabs = TerminalTabsModel(workspacePath: fixture.root.path)
        defer { tabs.closeAll() }

        tabs.previewFile(fixture.url("A.swift"))
        tabs.promotePreview(for: fixture.url("A.swift"))
        tabs.promotePreview(for: fixture.url("A.swift"))

        #expect(tabs.previewFileTabCount == 0)
        #expect(tabs.selectedFileDisposition == .permanent)
        #expect(tabs.recentFileURLs == [fixture.url("A.swift").standardizedFileURL])
    }

    @Test("Permanent file routes stay permanent while Explorer preview remains replaceable")
    func permanentRoutesStayPermanent() throws {
        let fixture = try Fixture(names: ["Quick.swift", "Preview.swift", "Next.swift"])
        defer { fixture.remove() }
        let tabs = TerminalTabsModel(workspacePath: fixture.root.path)
        defer { tabs.closeAll() }

        tabs.openFile(fixture.url("Quick.swift"))
        tabs.previewFile(fixture.url("Preview.swift"))
        tabs.previewFile(fixture.url("Next.swift"))

        #expect(tabs.fileTabCount == 2)
        #expect(tabs.previewFileURL == fixture.url("Next.swift").standardizedFileURL)
        #expect(tabs.recentFileURLs == [fixture.url("Quick.swift").standardizedFileURL])

        tabs.promotePreview(for: fixture.url("Next.swift"))

        #expect(tabs.previewFileTabCount == 0)
        #expect(tabs.recentFileURLs == [
            fixture.url("Next.swift").standardizedFileURL,
            fixture.url("Quick.swift").standardizedFileURL
        ])
    }

    @Test("Closing all tabs clears preview state without changing terminal rules")
    func closeAllClearsPreview() throws {
        let fixture = try Fixture(names: ["A.swift"])
        defer { fixture.remove() }
        let tabs = TerminalTabsModel(workspacePath: fixture.root.path)

        tabs.previewFile(fixture.url("A.swift"))
        #expect(tabs.terminalCount == 1)
        #expect(tabs.previewFileTabCount == 1)

        tabs.closeAll()

        #expect(tabs.terminalCount == 0)
        #expect(tabs.fileTabCount == 0)
        #expect(tabs.previewFileTabCount == 0)
        #expect(tabs.recentFileURLs.isEmpty)
    }

    @Test("Path paste targets only the selected terminal")
    func pathPasteTarget() throws {
        let fixture = try Fixture(names: ["A.swift"])
        defer { fixture.remove() }
        let tabs = TerminalTabsModel(workspacePath: fixture.root.path)
        defer { tabs.closeAll() }

        #expect(tabs.pasteIntoSelectedTerminal("@Sources/App.swift "))
        tabs.openFile(fixture.url("A.swift"))
        #expect(!tabs.pasteIntoSelectedTerminal("@Sources/App.swift "))
    }

    @Test("Removing a tree item closes descendant tabs and clears stale history")
    func closeFilesForTreeMutation() throws {
        let fixture = try Fixture(names: ["Keep.swift"])
        defer { fixture.remove() }
        let folder = fixture.url("Sources")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let nestedFile = folder.appendingPathComponent("Feature.swift")
        try Data("let feature = true\n".utf8).write(to: nestedFile)
        let tabs = TerminalTabsModel(workspacePath: fixture.root.path)
        defer { tabs.closeAll() }

        tabs.openFile(nestedFile)
        tabs.openFile(fixture.url("Keep.swift"))
        tabs.closeFiles(atOrUnder: folder)

        #expect(tabs.fileTabCount == 1)
        #expect(tabs.selectedFileURL == fixture.url("Keep.swift").standardizedFileURL)
        #expect(tabs.recentFileURLs == [fixture.url("Keep.swift").standardizedFileURL])
        #expect(!tabs.canNavigateBack)
    }

    private func target(_ name: String) -> FileNavigationTarget {
        FileNavigationTarget(
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            disposition: .permanent
        )
    }
}

private struct Fixture {
    let root: URL

    init(names: [String]) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("atelier-navigation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for name in names {
            try Data("let value = 1\n".utf8).write(to: url(name))
        }
    }

    func url(_ name: String) -> URL {
        root.appendingPathComponent(name)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
