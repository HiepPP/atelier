import Foundation
import Testing
@testable import Atelier

@Suite("Atelier core")
struct AtelierTests {
    @Test("Workspace persistence round-trips state")
    func workspacePersistence() async throws {
        let root = temporaryDirectory("workspace-persistence")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fileURL = root.appendingPathComponent("state.json")
        let state = WorkspaceState(path: root.path, bookmark: nil, lastOpenedAt: Date(timeIntervalSince1970: 1))
        let service = WorkspacePersistenceService(fileURL: fileURL)

        try await service.save(state)
        let loaded = try await service.load()

        #expect(loaded == state)
    }

    @Test("File loader classifies text, binary, and large files")
    func fileLoading() async throws {
        let root = temporaryDirectory("file-loader")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let textURL = root.appendingPathComponent("text.txt")
        let binaryURL = root.appendingPathComponent("binary.bin")
        let largeURL = root.appendingPathComponent("large.txt")
        let imageURL = root.appendingPathComponent("pixel.png")
        let imageData = try #require(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        ))
        try Data("hello".utf8).write(to: textURL)
        try Data([0x41, 0x00, 0x42]).write(to: binaryURL)
        try Data(repeating: 0x41, count: 9).write(to: largeURL)
        try imageData.write(to: imageURL)

        #expect(await FileLoader.loadAsync(url: textURL) == .text("hello"))
        #expect(FileLoader.load(url: binaryURL) == .binary)
        #expect(FileLoader.load(url: largeURL, limit: 8) == .tooLarge(9))
        #expect(await FileLoader.loadAsync(url: imageURL) == .image(imageData))
        #expect(FileLoader.load(url: imageURL, imageLimit: 8) == .tooLarge(imageData.count))
    }

    @Test("File tree filters ignored paths and sorts directories first")
    func fileTree() async throws {
        let root = temporaryDirectory("file-tree")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Sources"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".git"),
            withIntermediateDirectories: true
        )
        try Data().write(to: root.appendingPathComponent("README.md"))

        let entries = try await FileTreeService().children(of: root)

        #expect(entries.map { $0.url.lastPathComponent } == ["Sources", "README.md"])
    }

    @Test("File tree service creates files and folders without overwriting")
    func fileTreeCreation() async throws {
        let root = temporaryDirectory("file-tree-creation")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let service = FileTreeService()

        let fileURL = try await service.createFile(named: "main.swift", in: root)
        let folderURL = try await service.createFolder(named: "Sources", in: root)
        let nestedFileURL = try await service.createFile(named: "Feature.swift", in: folderURL)

        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
        #expect(FileManager.default.fileExists(atPath: nestedFileURL.path))

        do {
            _ = try await service.createFile(named: "main.swift", in: root)
            Issue.record("Creating a duplicate file should fail")
        } catch let error as FileTreeServiceError {
            guard case .alreadyExists = error else {
                Issue.record("Expected an already-exists error")
                return
            }
        }

        do {
            _ = try await service.createFolder(named: "../Outside", in: root)
            Issue.record("Creating an invalid path should fail")
        } catch let error as FileTreeServiceError {
            guard case .invalidName = error else {
                Issue.record("Expected an invalid-name error")
                return
            }
        }
    }

    @Test("Git porcelain parser preserves rename and conflict details")
    func gitParsing() {
        let sample = [
            "2 R. N... 100644 100644 100644 abcdef1 abcdef2 R100 renamed.txt",
            "old.txt",
            "u UU N... 100644 100644 100644 100644 abcdef1 abcdef2 abcdef3 conflict.txt",
            "? new file.txt",
            ""
        ].joined(separator: "\0")

        let status = GitStatus.parse(Data(sample.utf8))

        #expect(status.changes.contains {
            $0.path == "renamed.txt" && $0.originalPath == "old.txt" && $0.kind == .renamed
        })
        #expect(status.changes.contains { $0.path == "conflict.txt" && $0.kind == .conflicted })
        #expect(status.untracked.map(\.path) == ["new file.txt"])
    }

    @Test("Editor documents use standardized URL identity")
    func editorDocumentIdentity() {
        let root = temporaryDirectory("editor-document")
        let first = EditorDocument(url: root.appendingPathComponent("a/../main.swift"))
        let second = EditorDocument(url: root.appendingPathComponent("main.swift"))

        #expect(first.id == second.id)
        #expect(first.displayName == "main.swift")
    }

    @Test("Terminal advertises ANSI and true-color support")
    func terminalEnvironment() {
        let environment = TerminalProcessService.configuredEnvironment(from: [
            "TERM": "dumb",
            "PATH": "/usr/bin"
        ])

        #expect(environment["TERM"] == "xterm-256color")
        #expect(environment["COLORTERM"] == "truecolor")
        #expect(environment["CLICOLOR"] == "1")
        #expect(environment["TERM_PROGRAM"] == "Atelier")
        #expect(environment["PATH"] == "/usr/bin")
    }

    private func temporaryDirectory(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("atelier-tests-\(name)-\(UUID().uuidString)", isDirectory: true)
    }
}
