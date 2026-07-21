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

        let catalog = WorkspaceCatalogState(workspaces: [state], selectedWorkspaceID: state.id)
        try await service.save(catalog)
        let loaded = try await service.load()

        #expect(loaded == catalog)
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

    @Test("Editor fully lays out every previewable text file")
    func editorLayoutPolicy() {
        #expect(FileLayoutPolicy.maximumFullLayoutBytes == FileLoader.defaultLimit)
        #expect(FileLayoutPolicy.usesFullLayout(byteCount: FileLoader.defaultLimit))
        #expect(!FileLayoutPolicy.usesFullLayout(byteCount: FileLoader.defaultLimit + 1))
    }

    @Test("Editor session routes every file find action to its surface")
    func editorFindActions() async throws {
        let root = temporaryDirectory("editor-find")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fileURL = root.appendingPathComponent("Search.swift")
        try Data("let searchTarget = true\n".utf8).write(to: fileURL)
        let session = EditorSession(url: fileURL)
        let surface = EditorFindSurfaceRecorder(document: session.document)
        session.attach(surface: surface)

        for _ in 0..<100 where !session.canFindInFile {
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(session.canFindInFile)

        for action in EditorFindAction.allCases {
            session.performFindAction(action)
        }
        #expect(surface.actions == EditorFindAction.allCases)

        session.detach(surface: surface)
        session.performFindAction(.nextMatch)
        #expect(surface.actions == EditorFindAction.allCases)
        session.close()
    }

    @Test("Editor selection references use UTF-16 line ranges")
    func editorSelectionReferences() throws {
        let text = "first\nemoji 👩🏽‍💻\nthird\nfourth"
        let source = text as NSString
        let selection = source.range(of: "emoji 👩🏽‍💻\nthird")
        let lineRange = try #require(
            EditorSelectionReferencePolicy.lineRange(in: text, selection: selection)
        )

        #expect(lineRange == 2...3)
        #expect(EditorSelectionReferencePolicy.lineRange(
            in: text,
            selection: NSRange(location: 0, length: 6)
        ) == 1...1)
        #expect(EditorSelectionReferencePolicy.lineRange(
            in: text,
            selection: NSRange(location: 0, length: 0)
        ) == nil)
        #expect(EditorSelectionReferencePolicy.reference(
            fileURL: URL(fileURLWithPath: "/tmp/project/apps/catalog.ts"),
            workspaceRootURL: URL(fileURLWithPath: "/tmp/project", isDirectory: true),
            lineRange: 10...15
        ) == "@apps/catalog.ts:10~15 ")
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

        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("README-link.md"),
            withDestinationURL: root.appendingPathComponent("README.md")
        )
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("Sources-link"),
            withDestinationURL: root.appendingPathComponent("Sources", isDirectory: true)
        )

        let entriesWithLinks = try await FileTreeService().children(of: root)
        let fileLink = try #require(
            entriesWithLinks.first { $0.url.lastPathComponent == "README-link.md" }
        )
        let folderLink = try #require(
            entriesWithLinks.first { $0.url.lastPathComponent == "Sources-link" }
        )

        #expect(fileLink.isSymbolicLink)
        #expect(!fileLink.isDirectory)
        #expect(!fileLink.symbolicLinkTargetIsDirectory)
        #expect(folderLink.isSymbolicLink)
        #expect(!folderLink.isDirectory)
        #expect(folderLink.symbolicLinkTargetIsDirectory)
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

    @Test("File tree paths stay relative to the workspace")
    func fileTreeRelativePaths() {
        let root = URL(fileURLWithPath: "/tmp/atelier-workspace", isDirectory: true)

        #expect(FileTreePathPolicy.relativePath(
            of: root.appendingPathComponent("Sources", isDirectory: true),
            within: root
        ) == "Sources")
        #expect(FileTreePathPolicy.relativePath(
            of: root.appendingPathComponent("Sources/App.swift"),
            within: root
        ) == "Sources/App.swift")
        #expect(FileTreePathPolicy.relativePath(
            of: URL(fileURLWithPath: "/tmp/atelier-workspace-copy/App.swift"),
            within: root
        ) == nil)
        #expect(
            FileTreePathPolicy.terminalReference(for: "Sources/App.swift")
                == "@Sources/App.swift "
        )
    }

    @Test("File tree renames items and appends stable Git ignore patterns")
    func fileTreeItemActions() async throws {
        let root = temporaryDirectory("file-tree-actions")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let service = FileTreeService()
        let original = try await service.createFile(named: "Draft[1]*.md", in: root)

        let renamed = try await service.renameItem(at: original, to: "Final[1]*.md")
        #expect(!FileManager.default.fileExists(atPath: original.path))
        #expect(FileManager.default.fileExists(atPath: renamed.path))

        try await service.addToGitIgnore(renamed, workspaceRoot: root)
        try await service.addToGitIgnore(renamed, workspaceRoot: root)
        let gitIgnore = try String(
            contentsOf: root.appendingPathComponent(".gitignore"),
            encoding: .utf8
        )
        #expect(gitIgnore == "/Final\\[1\\]\\*.md\n")
    }

    @Test("Git ignore presentation matches exact items and descendants")
    func fileTreeGitIgnorePresentation() {
        let root = URL(fileURLWithPath: "/workspace", isDirectory: true)
        let ignoredPaths = FileTreeGitIgnorePresentation.normalized(["tmp/", "generated.txt"])

        #expect(FileTreeGitIgnorePresentation.isIgnored(
            root.appendingPathComponent("tmp", isDirectory: true),
            rootURL: root,
            ignoredPaths: ignoredPaths
        ))
        #expect(FileTreeGitIgnorePresentation.isIgnored(
            root.appendingPathComponent("tmp/result.txt"),
            rootURL: root,
            ignoredPaths: ignoredPaths
        ))
        #expect(FileTreeGitIgnorePresentation.isIgnored(
            root.appendingPathComponent("generated.txt"),
            rootURL: root,
            ignoredPaths: ignoredPaths
        ))
        #expect(!FileTreeGitIgnorePresentation.isIgnored(
            root.appendingPathComponent("tmp-copy/result.txt"),
            rootURL: root,
            ignoredPaths: ignoredPaths
        ))
    }

    @Test("Git porcelain parser preserves rename and conflict details")
    func gitParsing() {
        let sample = [
            "2 R. N... 100644 100644 100644 abcdef1 abcdef2 R100 renamed.txt",
            "old.txt",
            "u UU N... 100644 100644 100644 100644 abcdef1 abcdef2 abcdef3 conflict.txt",
            "? new file.txt",
            "! tmp/",
            ""
        ].joined(separator: "\0")

        let status = GitStatus.parse(Data(sample.utf8))

        #expect(status.changes.contains {
            $0.path == "renamed.txt" && $0.originalPath == "old.txt" && $0.kind == .renamed
        })
        #expect(status.changes.contains { $0.path == "conflict.txt" && $0.kind == .conflicted })
        #expect(status.untracked.map(\.path) == ["new file.txt"])
        #expect(status.ignoredPaths == ["tmp/"])
    }

    @Test("Git log parser preserves commit metadata")
    func gitCommitLogParsing() {
        let sample = [
            "abcdef123456\u{001F}abcdef1\u{001F}Hiệp\u{001F}zendragon93@gmail.com\u{001F}1721600000\u{001F}feat: add git history\u{001E}",
            "123456789abc\u{001F}1234567\u{001F}Atelier Bot\u{001F}41898282+atelier-bot@users.noreply.github.com\u{001F}1721500000\u{001F}fix: refresh status\u{001E}"
        ].joined()

        let commits = GitCommitLogParser.parse(Data(sample.utf8))

        #expect(commits.count == 2)
        #expect(commits[0].hash == "abcdef123456")
        #expect(commits[0].shortHash == "abcdef1")
        #expect(commits[0].author == "Hiệp")
        #expect(commits[0].authorEmail == "zendragon93@gmail.com")
        #expect(
            commits[0].authorAvatarURL?.absoluteString
                == "https://www.gravatar.com/avatar/390834babe332991b4c17ce93aa24f20?d=404&s=96"
        )
        #expect(commits[0].subject == "feat: add git history")
        #expect(
            commits[1].authorAvatarURL?.absoluteString
                == "https://github.com/atelier-bot.png?size=96"
        )
        #expect(commits[1].subject == "fix: refresh status")
    }

    @Test("Git push enables for changes and stages all when needed")
    func gitPushPolicy() {
        let workingOnly = GitStatus(changes: [
            GitChange(
                path: "main.swift",
                originalPath: nil,
                kind: .modified,
                isStaged: false,
                isUnstaged: true
            )
        ])
        let staged = GitStatus(changes: [
            GitChange(
                path: "main.swift",
                originalPath: nil,
                kind: .modified,
                isStaged: true,
                isUnstaged: false
            )
        ])

        #expect(GitCommitPolicy.canPush(status: workingOnly))
        #expect(GitCommitPolicy.canPush(status: staged))
        #expect(!GitCommitPolicy.canPush(status: GitStatus(changes: [])))
        #expect(GitCommitPolicy.shouldStageAll(status: workingOnly))
        #expect(!GitCommitPolicy.shouldStageAll(status: staged))
    }

    @Test("Git changes form a compact directory tree")
    func gitChangeTree() throws {
        let changes = [
            GitChange(
                path: ".claude/skills/baconsua-content/cms_ops.sh",
                originalPath: nil,
                kind: .modified,
                isStaged: false,
                isUnstaged: true
            ),
            GitChange(
                path: "docs/baconsua.sqlite",
                originalPath: nil,
                kind: .modified,
                isStaged: false,
                isUnstaged: true
            ),
            GitChange(
                path: "docs/baconsua.sqlite.dump.tsv",
                originalPath: nil,
                kind: .modified,
                isStaged: false,
                isUnstaged: true
            ),
            GitChange(
                path: "generated-assets/20260722-article/article.mdx",
                originalPath: nil,
                kind: .untracked,
                isStaged: false,
                isUnstaged: true
            )
        ]

        let roots = GitChangeTreeBuilder.build(changes)

        #expect(roots.map(\.name) == [
            ".claude/skills/baconsua-content",
            "docs",
            "generated-assets/20260722-article"
        ])
        let scripts = try #require(roots.first { $0.name.hasPrefix(".claude/") })
        let docs = try #require(roots.first { $0.name == "docs" })
        let generated = try #require(roots.first { $0.name.hasPrefix("generated-assets/") })
        #expect(scripts.children.map(\.name) == ["cms_ops.sh"])
        #expect(docs.children.map(\.name) == [
            "baconsua.sqlite",
            "baconsua.sqlite.dump.tsv"
        ])
        let article = try #require(generated.children.first?.change)
        #expect(article.path == "generated-assets/20260722-article/article.mdx")
    }

    @Test("Git change tree folders count descendant files")
    func gitChangeTreeFolderCounts() throws {
        let changes = [
            GitChange(
                path: "docs/one.md",
                originalPath: nil,
                kind: .modified,
                isStaged: false,
                isUnstaged: true
            ),
            GitChange(
                path: "docs/nested/two.md",
                originalPath: nil,
                kind: .untracked,
                isStaged: false,
                isUnstaged: true
            )
        ]

        let root = try #require(GitChangeTreeBuilder.build(changes).first)
        let nested = try #require(root.children.first { $0.isFolder })

        #expect(root.changeCount == 2)
        #expect(nested.changeCount == 1)
    }

    @Test("Git subprocess finds user-installed command-line tools")
    func gitProcessEnvironment() {
        let environment = GitProcessEnvironment.configured(from: [
            "HOME": "/Users/tester",
            "PATH": "/usr/bin:/custom/bin:/usr/local/bin",
            "SSH_AUTH_SOCK": "/tmp/agent.sock"
        ])

        #expect(
            environment["PATH"]
                == "/usr/bin:/custom/bin:/usr/local/bin:/opt/homebrew/bin:/Users/tester/.local/bin"
        )
        #expect(environment["GIT_OPTIONAL_LOCKS"] == "0")
        #expect(environment["SSH_AUTH_SOCK"] == "/tmp/agent.sock")
    }

    @Test("Gemma commit message uses changed file paths without tools")
    func gitCommitMessageGeneration() async throws {
        let client = ScriptedOllamaClient(
            responses: [
                .chunks([
                    OllamaChatChunk(
                        message: OllamaChatMessage(
                            role: .assistant,
                            content: "fix(git): generate commit message"
                        ),
                        done: true
                    )
                ])
            ]
        )
        let generator = GitCommitMessageGenerator(client: client)

        let message = try await generator.generate(
            paths: ["README.md", "app/Atelier/Sources/Atelier/Git/ChangesView.swift", "README.md"]
        )

        #expect(message == "fix(git): generate commit message")
        let requests = await client.requests
        let request = try #require(requests.first)
        #expect(request.tools.isEmpty)
        #expect(request.messages.count == 2)
        #expect(
            request.messages.last?.content == """
            Changed file paths:
            - README.md
            - app/Atelier/Sources/Atelier/Git/ChangesView.swift
            """
        )
    }

    @Test("Git commit message generation times out and cancels transport")
    func gitCommitMessageTimeout() async {
        let client = ScriptedOllamaClient(responses: [.waiting])
        let generator = GitCommitMessageGenerator(
            client: client,
            timeout: .milliseconds(20)
        )

        await #expect(throws: GitCommitMessageError.timedOut) {
            _ = try await generator.generate(paths: ["README.md"])
        }
        #expect(await client.cancelCount == 1)
    }

    @Test("Git push generates a message, commits all changes, and pushes")
    func gitGeneratedPush() async throws {
        let root = temporaryDirectory("git-generated-push")
        let repository = root.appendingPathComponent("working", isDirectory: true)
        let remote = root.appendingPathComponent("remote.git", isDirectory: true)
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        let command = GitCommand()
        func git(_ arguments: [String], at directory: URL? = nil) throws -> Data {
            try command.run(
                arguments: arguments,
                workspacePath: (directory ?? repository).path
            )
        }

        _ = try git(["init", "--bare", "-q", remote.path], at: root)
        _ = try git(["init", "-q"])
        _ = try git(["config", "user.name", "Atelier Tests"])
        _ = try git(["config", "user.email", "atelier-tests@example.invalid"])
        _ = try git(["branch", "-M", "main"])
        _ = try git(["remote", "add", "origin", remote.path])
        let tracked = repository.appendingPathComponent("tracked.txt")
        try Data("before\n".utf8).write(to: tracked)
        _ = try git(["add", "--", "tracked.txt"])
        _ = try git(["commit", "-qm", "initial"])
        _ = try git(["push", "-qu", "origin", "main"])

        try Data("after\n".utf8).write(to: tracked)
        try Data("new\n".utf8).write(
            to: repository.appendingPathComponent("untracked.txt")
        )
        let client = ScriptedOllamaClient(
            responses: [
                .chunks([
                    OllamaChatChunk(
                        message: OllamaChatMessage(
                            role: .assistant,
                            content: "feat(git): push generated changes"
                        ),
                        done: true
                    )
                ])
            ]
        )
        let model = GitWorkspaceModel(
            workspacePath: repository.path,
            commitMessageClient: client
        )
        model.refresh()
        for _ in 0..<200 where model.isLoading || model.snapshot.status.changes.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.canPush)

        var generatedMessage: String?
        var didPush = false
        model.push(onGeneratedMessage: { generatedMessage = $0 }) {
            didPush = true
        }
        for _ in 0..<400 where !didPush && model.errorMessage == nil {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(didPush)
        #expect(model.pushPhase == .idle)
        #expect(model.errorMessage == nil)
        #expect(generatedMessage == "feat(git): push generated changes")
        let localHead = String(decoding: try git(["rev-parse", "HEAD"]), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let remoteHead = String(
            decoding: try git(
                ["--git-dir", remote.path, "rev-parse", "refs/heads/main"],
                at: root
            ),
            as: UTF8.self
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let subject = String(decoding: try git(["log", "-1", "--pretty=%s"]), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(localHead == remoteHead)
        #expect(subject == "feat(git): push generated changes")
    }

    @Test("Git service stages tracked and untracked changes together")
    func gitStageAll() async throws {
        let repository = temporaryDirectory("git-stage-all")
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        let command = GitCommand()
        func git(_ arguments: [String]) throws -> Data {
            try command.run(arguments: arguments, workspacePath: repository.path)
        }

        _ = try git(["init", "-q"])
        let tracked = repository.appendingPathComponent("tracked.txt")
        try Data("before\n".utf8).write(to: tracked)
        _ = try git(["add", "--", "tracked.txt"])
        _ = try git([
            "-c", "user.name=Atelier Tests",
            "-c", "user.email=atelier-tests@example.invalid",
            "commit", "-qm", "initial"
        ])

        try Data("after\n".utf8).write(to: tracked)
        try Data("new\n".utf8).write(
            to: repository.appendingPathComponent("untracked.txt")
        )
        try await GitService().stageAll(workspacePath: repository.path)

        let stagedPaths = String(decoding: try git(["diff", "--cached", "--name-only"]), as: UTF8.self)
            .split(whereSeparator: \Character.isNewline)
            .map(String.init)
        #expect(stagedPaths == ["tracked.txt", "untracked.txt"])
    }

    @Test("Unified diff parser tracks old and new line numbers")
    func gitDiffParsing() throws {
        let document = GitDiffDocument(text: """
        diff --git a/main.swift b/main.swift
        index 1111111..2222222 100644
        --- a/main.swift
        +++ b/main.swift
        @@ -1,3 +1,4 @@
         let first = 1
        -let second = 2
        +let second = 3
        +let third = 4
        """)

        #expect(document.additions == 2)
        #expect(document.deletions == 1)

        let context = try #require(document.lines.first { $0.kind == .context })
        let deletion = try #require(document.lines.first { $0.kind == .deletion })
        let additions = document.lines.filter { $0.kind == .addition }

        #expect(context.oldLineNumber == 1)
        #expect(context.newLineNumber == 1)
        #expect(deletion.oldLineNumber == 2)
        #expect(deletion.newLineNumber == nil)
        #expect(additions.map(\.newLineNumber) == [2, 3])
        #expect(additions.allSatisfy { $0.oldLineNumber == nil })
    }

    @Test("Git diff tabs reuse identity and close without affecting file tabs")
    @MainActor
    func gitDiffTabLifecycle() throws {
        let root = temporaryDirectory("git-diff-tabs")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fileURL = root.appendingPathComponent("main.swift")
        try Data("let value = 1\n".utf8).write(to: fileURL)
        let selection = DiffSelection(
            change: GitChange(
                path: "main.swift",
                originalPath: nil,
                kind: .untracked,
                isStaged: false,
                isUnstaged: true
            ),
            staged: false
        )
        let tabs = TerminalTabsModel(workspacePath: root.path)
        defer { tabs.closeAll() }

        tabs.openFile(fileURL)
        tabs.openFile(fileURL)
        #expect(tabs.fileTabCount == 1)

        tabs.openGitDiff(selection)
        let firstDiffID = tabs.selectedID
        tabs.openGitDiff(selection)

        #expect(tabs.gitDiffTabCount == 1)
        #expect(tabs.selectedID == firstDiffID)
        #expect(tabs.selectedGitDiffSelection == selection)

        tabs.closeSelectedTab()

        #expect(tabs.gitDiffTabCount == 0)
        #expect(tabs.fileTabCount == 1)
        #expect(tabs.selectedGitDiffSelection == nil)
    }

    @Test("Agent sidecar eligibility follows the selected center tab")
    @MainActor
    func agentSidecarTabEligibility() throws {
        let root = temporaryDirectory("agent-sidecar-tabs")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fileURL = root.appendingPathComponent("main.swift")
        try Data("let value = 1\n".utf8).write(to: fileURL)
        let tabs = TerminalTabsModel(workspacePath: root.path)
        defer { tabs.closeAll() }

        #expect(tabs.isTerminalSelected)
        tabs.openFile(fileURL)
        #expect(!tabs.isTerminalSelected)
        tabs.closeSelectedTab()
        #expect(tabs.isTerminalSelected)
    }

    @Test("Selected tab exposes stable inspector context")
    @MainActor
    func selectedTabInspectorContext() async throws {
        let root = temporaryDirectory("tab-inspector-context")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fileURL = root.appendingPathComponent("main.swift")
        try Data("let value = 1\n".utf8).write(to: fileURL)
        let selection = DiffSelection(
            change: GitChange(
                path: "main.swift",
                originalPath: nil,
                kind: .untracked,
                isStaged: false,
                isUnstaged: true
            ),
            staged: false
        )
        let tabs = TerminalTabsModel(workspacePath: root.path)
        defer { tabs.closeAll() }

        let terminal = try #require(tabs.selectedInspectorContext)
        #expect(terminal.kind == .terminal)
        #expect(terminal.status == "Running")
        #expect(terminal.showsActivity)
        #expect(terminal.details.contains {
            $0.label == "Working directory" && $0.value == root.path
        })

        tabs.openFile(fileURL)
        let file = try #require(tabs.selectedInspectorContext)
        #expect(file.kind == .file)
        #expect(file.title == "main.swift")
        #expect(!file.showsActivity)
        #expect(file.details.contains { $0.label == "Word wrap" && $0.value == "On" })

        tabs.openGitDiff(selection)
        var diff = try #require(tabs.selectedInspectorContext)
        #expect(diff.kind == .gitDiff)
        #expect(diff.details.contains {
            $0.label == "Change" && $0.value == "Untracked"
        })

        // Untracked files load an all-additions diff via git diff --no-index.
        for _ in 0..<100 where diff.status == "Loading" {
            try await Task.sleep(for: .milliseconds(20))
            diff = try #require(tabs.selectedInspectorContext)
        }
        #expect(diff.status == "Ready")
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
            "NO_COLOR": "1",
            "PATH": "/usr/bin"
        ])

        #expect(environment["TERM"] == "xterm-256color")
        #expect(environment["COLORTERM"] == "truecolor")
        #expect(environment["CLICOLOR"] == "1")
        #expect(environment["TERM_PROGRAM"] == "Atelier")
        #expect(environment["NO_COLOR"] == nil)
        #expect(environment["PATH"] == "/usr/bin")
    }

    @Test("Legacy terminal routes multiline input and TUI arrows")
    func terminalLegacyKeyFallback() throws {
        let sequence: (UInt16, TerminalLegacyKeyPolicy.SpecialKey?, String?, Bool) -> [UInt8]? = {
            keyCode, specialKey, characters, shift in
            TerminalLegacyKeyPolicy.sequence(
                keyCode: keyCode,
                specialKey: specialKey,
                charactersIgnoringModifiers: characters,
                shift: shift,
                control: false,
                option: false,
                command: false
            )
        }

        #expect(sequence(36, nil, "\r", false) == nil)
        #expect(sequence(36, nil, "\r", true) == [0x0A])
        #expect(sequence(0, .upArrow, nil, false) == [0x1B, 0x5B, 0x41])
        #expect(sequence(0, .downArrow, nil, false) == [0x1B, 0x5B, 0x42])
        #expect(sequence(0, .leftArrow, nil, false) == [0x1B, 0x5B, 0x44])
        #expect(sequence(0, .rightArrow, nil, false) == [0x1B, 0x5B, 0x43])
        #expect(sequence(126, nil, nil, true) == nil)
        #expect(sequence(126, nil, nil, false) == [0x1B, 0x5B, 0x41])
        #expect(sequence(0, nil, String(try #require(UnicodeScalar(0xF700))), false) == [0x1B, 0x5B, 0x41])
    }

    @Test("Terminal caps Mermaid width and keeps narrow layouts contained")
    func terminalMermaidRenderWidth() {
        #expect(MermaidRenderingPolicy.targetWidth(containerWidth: 300) == 300)
        #expect(MermaidRenderingPolicy.targetWidth(containerWidth: 800) == 720)
        #expect(MermaidRenderingPolicy.targetWidth(containerWidth: 1_600) == 960)
    }

    @Test("Terminal detects Mermaid only in Codex final answers")
    func terminalCodexMermaidResponse() {
        let transcript = """
        {"timestamp":"2026-07-17T08:00:00.000Z","type":"session_meta","payload":{"cwd":"/tmp/project"}}
        {"timestamp":"2026-07-17T08:00:01.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"```mermaid\\ngraph TD\\nBad --> Output\\n```"}]}}
        {"timestamp":"2026-07-17T08:00:02.000Z","type":"response_item","payload":{"type":"message","role":"assistant","phase":"final_answer","content":[{"type":"output_text","text":"Here is the chart.\\n```mermaid\\ngraph TD\\n  A --> B\\n```"}]}}
        """

        #expect(AgentTranscriptMermaidParser.extractLatest(
            from: transcript,
            workspacePath: "/tmp/project",
            modifiedAfter: Date(timeIntervalSince1970: 0)
        ) == "graph TD\n  A --> B")
        #expect(AgentTranscriptMermaidParser.sessionStartedAt(transcript) ==
            Date(timeIntervalSince1970: 1_784_275_200))
    }

    @Test("Terminal keeps every Mermaid chart in one assistant answer")
    func terminalMultipleMermaidResponses() {
        let transcript = """
        {"timestamp":"2026-07-17T08:00:00.000Z","type":"session_meta","payload":{"cwd":"/tmp/project"}}
        {"timestamp":"2026-07-17T08:00:02.000Z","type":"response_item","payload":{"type":"message","role":"assistant","phase":"final_answer","content":[{"type":"output_text","text":"```mermaid\\nflowchart LR\\nA --> B\\n```\\nThen another.\\n```mermaid\\nsequenceDiagram\\nUser->>Agent: Ask\\n```"}]}}
        """

        let diagrams = AgentTranscriptMermaidParser.extractAll(
            from: transcript,
            workspacePath: "/tmp/project",
            modifiedAfter: Date(timeIntervalSince1970: 0)
        )
        #expect(diagrams.map(\.source) == [
            "flowchart LR\nA --> B",
            "sequenceDiagram\nUser->>Agent: Ask"
        ])
        #expect(Set(diagrams.map(\.id)).count == 2)
    }

    @Test("Terminal detects Mermaid only in Claude final responses")
    func terminalClaudeMermaidResponse() {
        let transcript = """
        {"timestamp":"2026-07-17T08:00:01.000Z","type":"assistant","cwd":"/tmp/project","message":{"role":"assistant","stop_reason":"tool_use","content":[{"type":"text","text":"```mermaid\\ngraph TD\\nWrong --> Phase\\n```"}]}}
        {"timestamp":"2026-07-17T08:00:02.000Z","type":"assistant","cwd":"/tmp/project","message":{"role":"assistant","stop_reason":"end_turn","content":[{"type":"text","text":"```mermaid\\nsequenceDiagram\\n  User->>Agent: Ask\\n```"}]}}
        """

        #expect(AgentTranscriptMermaidParser.extractLatest(
            from: transcript,
            workspacePath: "/tmp/project",
            modifiedAfter: Date(timeIntervalSince1970: 0)
        ) == "sequenceDiagram\n  User->>Agent: Ask")
    }

    @Test("Terminal ignores printed Mermaid and stale agent responses")
    func terminalIgnoresPrintedMermaid() {
        let printedOutput = "printf '```mermaid\\ngraph TD\\nA --> B\\n```'"
        let staleTranscript = """
        {"timestamp":"2026-07-17T08:00:00.000Z","type":"session_meta","payload":{"cwd":"/tmp/project"}}
        {"timestamp":"2026-07-17T08:00:01.000Z","type":"response_item","payload":{"type":"message","role":"assistant","phase":"final_answer","content":[{"type":"output_text","text":"```mermaid\\ngraph TD\\nA --> B\\n```"}]}}
        """

        #expect(MermaidMarkdownParser.extractLatest(from: printedOutput) == nil)
        #expect(AgentTranscriptMermaidParser.extractLatest(
            from: staleTranscript,
            workspacePath: "/tmp/project",
            modifiedAfter: Date(timeIntervalSince1970: 1_800_000_000)
        ) == nil)
    }

    private func temporaryDirectory(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("atelier-tests-\(name)-\(UUID().uuidString)", isDirectory: true)
    }
}

private final class EditorFindSurfaceRecorder: EditorSurface {
    var document: EditorDocument?
    private(set) var actions: [EditorFindAction] = []

    init(document: EditorDocument) {
        self.document = document
    }

    func open(_ document: EditorDocument) {
        self.document = document
    }

    func save() async throws {}

    func reveal(line: Int, column: Int) {}

    func focus() {}

    func performFindAction(_ action: EditorFindAction) {
        actions.append(action)
    }
}
