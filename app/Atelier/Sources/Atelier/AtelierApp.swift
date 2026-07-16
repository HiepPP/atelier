import SwiftUI
import AppKit

@main
struct AtelierApp: App {
    @StateObject private var store = WorkspaceStore()
    @StateObject private var zoom = AtelierZoomModel()

    init() {
        if CommandLine.arguments.contains("--selftest") {
            SelfTest.run()   // exit() bên trong
        }
        AtelierShortcuts.install()
    }

    var body: some Scene {
        WindowGroup("Atelier") {
            AtelierZoomContainer {
                ContentView()
                    .environmentObject(store)
                    .background(AtelierWorkspaceWindowMarker())
            }
            .environmentObject(zoom)
            .frame(
                minWidth: AtelierZoomModel.baseMinimumSize.width,
                minHeight: AtelierZoomModel.baseMinimumSize.height
            )
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Zoom In") {
                    AtelierShortcuts.maximizeWorkspaceWindow()
                    zoom.zoomIn()
                }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(!zoom.canZoomIn)

                Button("Zoom Out") {
                    zoom.zoomOut()
                }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(!zoom.canZoomOut)

                Button("Actual Size") {
                    zoom.reset()
                }
                .keyboardShortcut("0", modifiers: .command)

                Button(zoom.isFocusMode ? "Exit Focus Mode" : "Enter Focus Mode") {
                    zoom.toggleFocusMode()
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            }

            AtelierTabCommands()
        }

        Settings {
            AtelierSettingsView()
        }
    }
}

@MainActor
final class AtelierZoomModel: ObservableObject {
    static let baseMinimumSize = CGSize(width: 1_000, height: 600)

    @Published private(set) var scale: CGFloat = 1
    @Published private(set) var isFocusMode = false

    private static let minimumScale: CGFloat = 0.8
    private static let maximumScale: CGFloat = 2
    private static let defaultRenderScale: CGFloat = 1.5
    private static let chromeMaximumScale: CGFloat = 1.2
    private static let sidebarMaximumScale: CGFloat = 1.5
    private static let focusThresholdScale = sidebarMaximumScale / defaultRenderScale
    private static let step: CGFloat = 0.1
    private static let settleDelay: UInt64 = 200_000_000

    private var requestedScale: CGFloat = 1
    private var settleTask: Task<Void, Never>?
    private var focusModeIsAutomatic = false
    private weak var responderBeforeZoom: NSResponder?

    var canZoomIn: Bool { requestedScale < Self.maximumScale }
    var canZoomOut: Bool { requestedScale > Self.minimumScale }
    var chromeScale: CGFloat { min(renderScale, Self.chromeMaximumScale) }
    var sidebarScale: CGFloat { min(renderScale, Self.sidebarMaximumScale) }
    var contentScale: CGFloat { renderScale }

    private var renderScale: CGFloat {
        scale * Self.defaultRenderScale
    }

    func zoomIn() {
        requestScale(requestedScale + Self.step)
    }

    func zoomOut() {
        requestScale(requestedScale - Self.step)
    }

    func reset() {
        if requestedScale > Self.focusThresholdScale {
            focusModeIsAutomatic = true
        } else {
            isFocusMode = false
            focusModeIsAutomatic = false
        }
        requestScale(1)
    }

    func toggleFocusMode() {
        if isFocusMode {
            if requestedScale > Self.focusThresholdScale {
                focusModeIsAutomatic = true
                requestScale(Self.focusThresholdScale)
            } else {
                isFocusMode = false
                focusModeIsAutomatic = false
            }
        } else {
            isFocusMode = true
            focusModeIsAutomatic = false
        }
    }

    private func requestScale(_ value: CGFloat) {
        let clamped = min(Self.maximumScale, max(Self.minimumScale, value))
        requestedScale = (clamped * 100).rounded() / 100

        if settleTask == nil {
            responderBeforeZoom = AtelierShortcuts.currentWorkspaceFirstResponder()
        }
        settleTask?.cancel()

        settleTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: Self.settleDelay)
            } catch {
                return
            }
            guard let self else { return }
            updateFocusMode(for: requestedScale)
            if scale != requestedScale {
                scale = requestedScale
            }
            settleTask = nil
            AtelierShortcuts.restoreWorkspaceFirstResponder(responderBeforeZoom)
            responderBeforeZoom = nil
        }
    }

    private func updateFocusMode(for scale: CGFloat) {
        if scale > Self.focusThresholdScale, !isFocusMode {
            isFocusMode = true
            focusModeIsAutomatic = true
        } else if scale <= Self.focusThresholdScale, focusModeIsAutomatic {
            isFocusMode = false
            focusModeIsAutomatic = false
        }
    }
}

private struct AtelierZoomContainer<Content: View>: View {
    @EnvironmentObject private var zoom: AtelierZoomModel
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .environment(\.atelierZoomScale, zoom.chromeScale)
            .font(.system(size: 13 * zoom.chromeScale))
    }
}

/// Verify persist + reload logic không cần NSOpenPanel (panel là bước tay).
enum SelfTest {
    private final class AsyncErrorBox: @unchecked Sendable {
        private let lock = NSLock()
        private var error: Error?

        func set(_ error: Error?) {
            lock.lock()
            self.error = error
            lock.unlock()
        }

        func get() -> Error? {
            lock.lock()
            defer { lock.unlock() }
            return error
        }
    }

    static func run() -> Never {
        var pass = true
        func check(_ name: String, _ ok: Bool, _ detail: String) {
            print("[\(ok ? "PASS" : "FAIL")] \(name): \(detail)")
            if !ok { pass = false }
        }

        // fileURL tạm, không đụng state thật.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("atelier-selftest-\(ProcessInfo.processInfo.processIdentifier)/state.json")
        try? FileManager.default.removeItem(at: tmp.deletingLastPathComponent())

        // Folder thật để tạo bookmark hợp lệ.
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("atelier-ws-\(ProcessInfo.processInfo.processIdentifier)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let bookmark = try? folder.bookmarkData(
            options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)

        // 1. Set + save.
        let store1 = WorkspaceStore(fileURL: tmp)
        store1.setWorkspace(WorkspaceState(path: folder.path, bookmark: bookmark, lastOpenedAt: Date()))
        check("save JSON", FileManager.default.fileExists(atPath: tmp.path), "file=\(tmp.path)")

        // 2. Reload bằng store mới cùng fileURL.
        let store2 = WorkspaceStore(fileURL: tmp)
        check("reload workspace",
              store2.current?.path == folder.path,
              "loaded=\(store2.current?.path ?? "nil")")

        // 3. Bookmark resolve (folder còn tồn tại).
        check("bookmark resolve", store2.current != nil, "current set after resolve")

        // 4. Clear -> file bị xoá, load rỗng.
        store2.clearWorkspace()
        let store3 = WorkspaceStore(fileURL: tmp)
        check("clear -> empty", store3.current == nil, "current=\(String(describing: store3.current))")

        // 5. FileLoader phân loại text, binary, và file quá lớn.
        let loaderFolder = tmp.deletingLastPathComponent().appendingPathComponent("loader")
        try? FileManager.default.createDirectory(at: loaderFolder, withIntermediateDirectories: true)
        let textURL = loaderFolder.appendingPathComponent("text.txt")
        let binaryURL = loaderFolder.appendingPathComponent("binary.bin")
        let largeURL = loaderFolder.appendingPathComponent("large.txt")
        try? Data("hello".utf8).write(to: textURL)
        try? Data([0x41, 0x00, 0x42]).write(to: binaryURL)
        try? Data(repeating: 0x41, count: 9).write(to: largeURL)
        check("FileLoader text", FileLoader.load(url: textURL) == .text("hello"), "text decoded")
        check("FileLoader binary", FileLoader.load(url: binaryURL) == .binary, "null byte detected")
        check("FileLoader tooLarge", FileLoader.load(url: largeURL, limit: 8) == .tooLarge(9), "size capped")

        // 6. Porcelain v2 parser phân tách staged, unstaged, và untracked.
        let statusSample = [
            "1 M. N... 100644 100644 100644 abcdef1 abcdef2 staged.txt",
            "1 .M N... 100644 100644 100644 abcdef1 abcdef1 unstaged.txt",
            "? new file.txt",
            ""
        ].joined(separator: "\0")
        let status = GitStatus.parse(Data(statusSample.utf8))
        check("GitStatus staged", status.staged.map(\.path) == ["staged.txt"], "\(status.staged.map(\.path))")
        check("GitStatus unstaged", status.unstaged.map(\.path) == ["unstaged.txt"], "\(status.unstaged.map(\.path))")
        check("GitStatus untracked", status.untracked.map(\.path) == ["new file.txt"], "\(status.untracked.map(\.path))")

        let edgeStatusSample = [
            "2 R. N... 100644 100644 100644 abcdef1 abcdef2 R100 renamed.txt",
            "old.txt",
            "u UU N... 100644 100644 100644 100644 abcdef1 abcdef2 abcdef3 conflict.txt",
            ""
        ].joined(separator: "\0")
        let edgeStatus = GitStatus.parse(Data(edgeStatusSample.utf8))
        check(
            "GitStatus rename",
            edgeStatus.changes.contains {
                $0.path == "renamed.txt" && $0.originalPath == "old.txt" && $0.kind == .renamed
            },
            "type 2 record and source path parsed"
        )
        check(
            "GitStatus conflict",
            edgeStatus.changes.contains {
                $0.path == "conflict.txt" && $0.kind == .conflicted
            },
            "unmerged record parsed"
        )

        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let gitStatusRuns = (try? GitCommand().run(
            arguments: ["status", "--porcelain=v2", "-z"],
            workspacePath: packageRoot.path
        )) != nil
        check("Git Process runner", gitStatusRuns, "argument-array status completed")

        let gitTestRoot = tmp.deletingLastPathComponent().appendingPathComponent("git")
        let renameRepo = gitTestRoot.appendingPathComponent("rename")
        let unbornRepo = gitTestRoot.appendingPathComponent("unborn")
        try? FileManager.default.createDirectory(at: renameRepo, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: unbornRepo, withIntermediateDirectories: true)

        let gitCommand = GitCommand()
        func git(_ arguments: [String], in repo: URL) throws -> Data {
            try gitCommand.run(arguments: arguments, workspacePath: repo.path)
        }
        func waitForUnstage(path: String, originalPath: String?, in repo: URL) -> Error? {
            let semaphore = DispatchSemaphore(value: 0)
            let errorBox = AsyncErrorBox()
            Task.detached {
                do {
                    try await GitService().unstage(
                        path: path,
                        originalPath: originalPath,
                        workspacePath: repo.path
                    )
                    errorBox.set(nil)
                } catch {
                    errorBox.set(error)
                }
                semaphore.signal()
            }
            semaphore.wait()
            return errorBox.get()
        }

        let oldName = "old name.txt"
        let newName = "new name.txt"
        let oldURL = renameRepo.appendingPathComponent(oldName)
        let newURL = renameRepo.appendingPathComponent(newName)
        do {
            _ = try git(["init", "-q"], in: renameRepo)
            try Data("rename content\n".utf8).write(to: oldURL)
            _ = try git(["add", "--", oldName], in: renameRepo)
            _ = try git([
                "-c", "user.name=Atelier Selftest",
                "-c", "user.email=atelier-selftest@example.invalid",
                "commit", "-qm", "initial"
            ], in: renameRepo)
            _ = try git(["mv", "--", oldName, newName], in: renameRepo)

            let error = waitForUnstage(path: newName, originalPath: oldName, in: renameRepo)
            let cached = try git(["diff", "--cached", "--name-only"], in: renameRepo)
            let worktreePreserved = FileManager.default.fileExists(atPath: newURL.path)
                && !FileManager.default.fileExists(atPath: oldURL.path)
            check(
                "Git unstage staged rename",
                error == nil && cached.isEmpty && worktreePreserved,
                "both rename pathspecs reset; renamed worktree file preserved"
            )
        } catch {
            check("Git unstage staged rename", false, error.localizedDescription)
        }

        let unbornName = "unborn file.txt"
        let unbornURL = unbornRepo.appendingPathComponent(unbornName)
        do {
            _ = try git(["init", "-q"], in: unbornRepo)
            try Data("staged content\n".utf8).write(to: unbornURL)
            _ = try git(["add", "--", unbornName], in: unbornRepo)
            try Data("worktree content\n".utf8).write(to: unbornURL)

            let error = waitForUnstage(path: unbornName, originalPath: nil, in: unbornRepo)
            let cached = try git(["ls-files", "--cached", "--", unbornName], in: unbornRepo)
            let worktree = try String(contentsOf: unbornURL, encoding: .utf8)
            check(
                "Git unstage unborn modified content",
                error == nil && cached.isEmpty && worktree == "worktree content\n",
                "index entry removed; modified worktree content preserved"
            )
        } catch {
            check("Git unstage unborn modified content", false, error.localizedDescription)
        }

        try? FileManager.default.removeItem(at: tmp.deletingLastPathComponent())
        try? FileManager.default.removeItem(at: folder)

        print(pass ? "\nSELFTEST: ALL PASS" : "\nSELFTEST: SOME FAIL")
        exit(pass ? 0 : 1)
    }
}
