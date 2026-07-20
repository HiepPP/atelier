import Foundation
import Testing
@testable import Atelier

@Suite("File tree node")
@MainActor
struct FileTreeNodeTests {
    private func entry(_ name: String, isDirectory: Bool = false) -> FileTreeEntry {
        FileTreeEntry(
            url: URL(fileURLWithPath: "/tmp/root/\(name)", isDirectory: isDirectory),
            isDirectory: isDirectory,
            isSymbolicLink: false,
            symbolicLinkTargetIsDirectory: false
        )
    }

    @Test("Initial apply reports change")
    func initialApplyReportsChange() {
        let node = FileTreeNode(url: URL(fileURLWithPath: "/tmp/root"), isDirectory: true)
        _ = node.beginLoading()
        #expect(node.apply([entry("a.swift"), entry("b", isDirectory: true)]))
    }

    @Test("Reapplying identical entries reports no change and keeps node identity")
    func identicalApplyReportsNoChange() {
        let node = FileTreeNode(url: URL(fileURLWithPath: "/tmp/root"), isDirectory: true)
        let entries = [entry("a.swift"), entry("b", isDirectory: true)]
        _ = node.beginLoading()
        _ = node.apply(entries)
        let firstChildren = node.children ?? []
        _ = node.beginLoading()
        #expect(!node.apply(entries))
        let secondChildren = node.children ?? []
        #expect(firstChildren.count == secondChildren.count)
        #expect(zip(firstChildren, secondChildren).allSatisfy { $0 === $1 })
    }

    @Test("Changed entries report change")
    func changedApplyReportsChange() {
        let node = FileTreeNode(url: URL(fileURLWithPath: "/tmp/root"), isDirectory: true)
        _ = node.beginLoading()
        _ = node.apply([entry("a.swift")])
        _ = node.beginLoading()
        #expect(node.apply([entry("a.swift"), entry("c.swift")]))
    }
}
