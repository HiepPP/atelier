import Foundation
import Testing
@testable import Atelier

@Suite("Workspace lifecycle")
@MainActor
struct WorkspaceLifecycleTests {
    @Test("Catalog persistence round-trips and decodes legacy state")
    func persistenceAndMigration() async throws {
        let root = temporaryDirectory("persistence")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let state = workspaceState(root)
        let catalog = WorkspaceCatalogState(workspaces: [state], selectedWorkspaceID: state.id)
        let catalogURL = root.appendingPathComponent("catalog.json")
        let service = WorkspacePersistenceService(fileURL: catalogURL)

        try await service.save(catalog)
        #expect(try await service.load() == catalog)

        let legacyURL = root.appendingPathComponent("legacy.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(state).write(to: legacyURL)
        #expect(
            try await WorkspacePersistenceService(fileURL: legacyURL).load()
                == WorkspaceCatalogState(workspaces: [state], selectedWorkspaceID: state.id)
        )
    }

    @Test("Duplicate standardized paths reuse one live session")
    func duplicateSelection() throws {
        let root = temporaryDirectory("duplicate")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let model = makeModel("duplicate")
        defer { model.stop() }

        try model.openWorkspace(workspaceState(root.appendingPathComponent("child/..")))
        let first = try #require(model.workspace)
        try model.openWorkspace(workspaceState(root))

        #expect(model.workspaceStates.count == 1)
        #expect(model.workspace === first)
    }

    @Test("Switching keeps isolated sessions alive")
    func switchingAndIsolation() throws {
        let firstRoot = temporaryDirectory("first")
        let secondRoot = temporaryDirectory("second")
        try FileManager.default.createDirectory(at: firstRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondRoot, withIntermediateDirectories: true)
        let model = makeModel("switch")
        defer { model.stop() }

        try model.openWorkspace(workspaceState(firstRoot))
        let first = try #require(model.workspace)
        first.terminalTabs.add()
        try model.openWorkspace(workspaceState(secondRoot))
        let second = try #require(model.workspace)

        #expect(first !== second)
        #expect(first.terminalTabs !== second.terminalTabs)
        #expect(first.terminalTabs.terminalCount == 2)
        #expect(second.terminalTabs.terminalCount == 1)
        #expect(first.isStarted)
        #expect(second.isStarted)

        model.selectWorkspace(id: first.state.id)
        #expect(model.workspace === first)
        #expect(first.terminalTabs.terminalCount == 2)
        #expect(second.isStarted)
    }

    @Test("Number shortcuts select the matching ordered workspace")
    func numberedWorkspaceSelection() throws {
        let firstRoot = temporaryDirectory("shortcut-first")
        let secondRoot = temporaryDirectory("shortcut-second")
        try FileManager.default.createDirectory(at: firstRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondRoot, withIntermediateDirectories: true)
        let model = makeModel("shortcut-selection")
        defer { model.stop() }

        try model.openWorkspace(workspaceState(firstRoot))
        try model.openWorkspace(workspaceState(secondRoot))

        model.selectWorkspace(shortcutNumber: 1)
        #expect(model.selectedWorkspaceID == firstRoot.standardizedFileURL.path)

        model.selectWorkspace(shortcutNumber: 2)
        #expect(model.selectedWorkspaceID == secondRoot.standardizedFileURL.path)

        model.selectWorkspace(shortcutNumber: 9)
        #expect(model.selectedWorkspaceID == secondRoot.standardizedFileURL.path)
    }

    @Test("Closing one session leaves another running")
    func closeAndShutdown() throws {
        let firstRoot = temporaryDirectory("close-first")
        let secondRoot = temporaryDirectory("close-second")
        try FileManager.default.createDirectory(at: firstRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondRoot, withIntermediateDirectories: true)
        let model = makeModel("close")

        try model.openWorkspace(workspaceState(firstRoot))
        let first = try #require(model.workspace)
        try model.openWorkspace(workspaceState(secondRoot))
        let second = try #require(model.workspace)
        model.closeWorkspace()

        #expect(!second.isStarted)
        #expect(first.isStarted)
        #expect(model.workspace === first)

        model.stop()
        #expect(!first.isStarted)
    }

    @Test("Closing an inactive workspace preserves active selection")
    func closeInactiveWorkspace() throws {
        let firstRoot = temporaryDirectory("close-inactive-first")
        let secondRoot = temporaryDirectory("close-inactive-second")
        try FileManager.default.createDirectory(at: firstRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondRoot, withIntermediateDirectories: true)
        let model = makeModel("close-inactive")
        defer { model.stop() }

        try model.openWorkspace(workspaceState(firstRoot))
        let first = try #require(model.workspace)
        try model.openWorkspace(workspaceState(secondRoot))
        let second = try #require(model.workspace)

        model.closeWorkspace(id: first.state.id)

        #expect(!first.isStarted)
        #expect(second.isStarted)
        #expect(model.workspace === second)
        #expect(model.workspaceStates.map(\.id) == [second.state.id])
    }

    @Test("Workspace reorder preserves sessions and selection")
    func reorderWorkspaces() throws {
        let firstRoot = temporaryDirectory("reorder-first")
        let secondRoot = temporaryDirectory("reorder-second")
        let thirdRoot = temporaryDirectory("reorder-third")
        for root in [firstRoot, secondRoot, thirdRoot] {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
        let model = makeModel("reorder")
        defer { model.stop() }

        try model.openWorkspace(workspaceState(firstRoot))
        try model.openWorkspace(workspaceState(secondRoot))
        try model.openWorkspace(workspaceState(thirdRoot))
        let selectedID = try #require(model.selectedWorkspaceID)

        model.moveWorkspace(id: firstRoot.path, relativeTo: thirdRoot.path, insertAfter: true)

        #expect(model.workspaceStates.map(\.id) == [secondRoot.path, thirdRoot.path, firstRoot.path])
        #expect(model.selectedWorkspaceID == selectedID)
        #expect(model.liveSessions.count == 3)
    }

    @Test("Missing workspace remains unavailable without blocking valid session")
    func unavailableRestore() async throws {
        let validRoot = temporaryDirectory("valid")
        let missingRoot = temporaryDirectory("missing")
        try FileManager.default.createDirectory(at: validRoot, withIntermediateDirectories: true)
        let valid = workspaceState(validRoot)
        let missing = workspaceState(missingRoot)
        let persistenceURL = temporaryDirectory("restore").appendingPathComponent("state.json")
        let persistence = WorkspacePersistenceService(fileURL: persistenceURL)
        try await persistence.save(
            WorkspaceCatalogState(
                workspaces: [missing, valid],
                selectedWorkspaceID: missing.id
            )
        )
        let model = makeModel("restore", persistence: persistence)
        defer { model.stop() }

        model.start()
        await waitUntil { model.workspaceItems.count == 2 && model.loadingWorkspaceIDs.isEmpty }

        #expect(model.workspace?.state.id == valid.id)
        #expect(model.workspaceItems.count == 2)
        #expect(model.workspaceItems.contains { item in
            guard item.id == missing.id else { return false }
            if case .unavailable = item.status { return true }
            return false
        })
    }

    @Test("Failed open remains unavailable instead of appearing inactive")
    func failedOpenStatus() throws {
        let missingRoot = temporaryDirectory("failed-open")
        let model = makeModel("failed-open")
        defer { model.stop() }

        #expect(throws: WorkspaceAccessError.self) {
            try model.openWorkspace(workspaceState(missingRoot))
        }

        let item = try #require(model.workspaceItems.first)
        #expect(item.id == missingRoot.standardizedFileURL.path)
        let isUnavailable: Bool
        if case .unavailable = item.status {
            isUnavailable = true
        } else {
            isUnavailable = false
        }
        #expect(isUnavailable)
    }

    @Test("Delayed startup restore merges user work without orphaning sessions")
    func delayedStartupRestoreMergesUserWork() async throws {
        let restoredRoot = temporaryDirectory("delayed-restored")
        let userRoot = temporaryDirectory("delayed-user")
        try FileManager.default.createDirectory(at: restoredRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: userRoot, withIntermediateDirectories: true)
        let restored = workspaceState(restoredRoot)
        let user = workspaceState(userRoot)
        let persistenceURL = temporaryDirectory("delayed-load").appendingPathComponent("state.json")
        try await WorkspacePersistenceService(fileURL: persistenceURL).save(
            WorkspaceCatalogState(workspaces: [restored], selectedWorkspaceID: restored.id)
        )
        let loadGate = TestGate()
        let persistence = WorkspacePersistenceService(
            fileURL: persistenceURL,
            beforeLoad: { await loadGate.wait() }
        )
        let model = makeModel("delayed-load", persistence: persistence)

        model.start()
        await loadGate.waitUntilEntered()
        try model.openWorkspace(user)
        let catalogBeforeLoadReturns = try await WorkspacePersistenceService(
            fileURL: persistenceURL
        ).load()
        #expect(catalogBeforeLoadReturns?.workspaces.map(\.id) == [restored.id])
        #expect(catalogBeforeLoadReturns?.selectedWorkspaceID == restored.id)
        await loadGate.open()
        await waitUntil { model.liveSessions.count == 2 }

        #expect(model.workspaceStates.map(\.id) == [user.id, restored.id])
        #expect(model.liveSessions.count == model.workspaceStates.count)
        #expect(model.selectedWorkspaceID == user.id)
        #expect(model.workspace?.state.id == user.id)
        await model.stop().value
    }

    @Test("Empty startup load releases deferred persistence")
    func emptyStartupLoadReleasesPersistence() async throws {
        let userRoot = temporaryDirectory("empty-load-user")
        try FileManager.default.createDirectory(at: userRoot, withIntermediateDirectories: true)
        let user = workspaceState(userRoot)
        let persistenceURL = temporaryDirectory("empty-load-state").appendingPathComponent("state.json")
        let loadGate = TestGate()
        let persistence = WorkspacePersistenceService(
            fileURL: persistenceURL,
            beforeLoad: { await loadGate.wait() }
        )
        let model = makeModel("empty-load", persistence: persistence)

        model.start()
        await loadGate.waitUntilEntered()
        try model.openWorkspace(user)
        #expect(!FileManager.default.fileExists(atPath: persistenceURL.path))

        await loadGate.open()
        await waitUntil { FileManager.default.fileExists(atPath: persistenceURL.path) }
        #expect(try await WorkspacePersistenceService(fileURL: persistenceURL).load()
            == WorkspaceCatalogState(workspaces: [user], selectedWorkspaceID: user.id))
        await model.stop().value
    }

    @Test("Failed startup load releases deferred persistence")
    func failedStartupLoadReleasesPersistence() async throws {
        let userRoot = temporaryDirectory("failed-load-user")
        try FileManager.default.createDirectory(at: userRoot, withIntermediateDirectories: true)
        let user = workspaceState(userRoot)
        let persistenceURL = temporaryDirectory("failed-load-state").appendingPathComponent("state.json")
        try FileManager.default.createDirectory(
            at: persistenceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let invalidData = Data("not-json".utf8)
        try invalidData.write(to: persistenceURL)
        let loadGate = TestGate()
        let persistence = WorkspacePersistenceService(
            fileURL: persistenceURL,
            beforeLoad: { await loadGate.wait() }
        )
        let model = makeModel("failed-load", persistence: persistence)

        model.start()
        await loadGate.waitUntilEntered()
        try model.openWorkspace(user)
        #expect(try Data(contentsOf: persistenceURL) == invalidData)

        await loadGate.open()
        await waitUntil { (try? Data(contentsOf: persistenceURL)) != invalidData }
        #expect(model.presentedError != nil)
        #expect(try await WorkspacePersistenceService(fileURL: persistenceURL).load()
            == WorkspaceCatalogState(workspaces: [user], selectedWorkspaceID: user.id))
        await model.stop().value
    }

    @Test("Stop releases deferred persistence while startup load is blocked")
    func stopReleasesBlockedStartupPersistence() async throws {
        let restoredRoot = temporaryDirectory("stop-restored")
        let userRoot = temporaryDirectory("stop-user")
        try FileManager.default.createDirectory(at: restoredRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: userRoot, withIntermediateDirectories: true)
        let restored = workspaceState(restoredRoot)
        let user = workspaceState(userRoot)
        let persistenceURL = temporaryDirectory("stop-load-state").appendingPathComponent("state.json")
        try await WorkspacePersistenceService(fileURL: persistenceURL).save(
            WorkspaceCatalogState(workspaces: [restored], selectedWorkspaceID: restored.id)
        )
        let loadGate = TestGate()
        let persistence = WorkspacePersistenceService(
            fileURL: persistenceURL,
            beforeLoad: { await loadGate.wait() }
        )
        let model = makeModel("stop-load", persistence: persistence)

        model.start()
        await loadGate.waitUntilEntered()
        try model.openWorkspace(user)
        await model.stop().value

        #expect(try await WorkspacePersistenceService(fileURL: persistenceURL).load()
            == WorkspaceCatalogState(workspaces: [user], selectedWorkspaceID: user.id))
        await loadGate.open()
    }

    @Test("Restore exposes loading state before activation")
    func observableLoadingState() async throws {
        let root = temporaryDirectory("loading")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let state = workspaceState(root)
        let persistenceURL = temporaryDirectory("loading-state").appendingPathComponent("state.json")
        try await WorkspacePersistenceService(fileURL: persistenceURL).save(
            WorkspaceCatalogState(workspaces: [state], selectedWorkspaceID: state.id)
        )
        let restoreGate = TestGate()
        let model = makeModel(
            "loading",
            persistence: WorkspacePersistenceService(fileURL: persistenceURL),
            scheduleWorkspaceRestore: { await restoreGate.wait() }
        )

        model.start()
        await restoreGate.waitUntilEntered()
        let loadingItem = try #require(model.workspaceItems.first)
        if case .loading = loadingItem.status {
            // Expected staged state.
        } else {
            Issue.record("Expected a loading catalog item before activation")
        }
        #expect(model.workspace == nil)

        await restoreGate.open()
        await waitUntil { model.workspace?.state.id == state.id }
        #expect(model.loadingWorkspaceIDs.isEmpty)
        await model.stop().value
    }

    @Test("Persistence rejects an older delayed save")
    func persistenceRejectsStaleSave() async throws {
        let firstRoot = temporaryDirectory("stale-first")
        let secondRoot = temporaryDirectory("stale-second")
        let fileURL = temporaryDirectory("stale-state").appendingPathComponent("state.json")
        let first = WorkspaceCatalogState(
            workspaces: [workspaceState(firstRoot)],
            selectedWorkspaceID: workspaceState(firstRoot).id
        )
        let second = WorkspaceCatalogState(
            workspaces: [workspaceState(secondRoot)],
            selectedWorkspaceID: workspaceState(secondRoot).id
        )
        let firstSaveGate = TestGate()
        let service = WorkspacePersistenceService(
            fileURL: fileURL,
            beforeSave: { revision, _ in
                if revision == 1 { await firstSaveGate.wait() }
            }
        )

        let olderSave = Task { try await service.save(first) }
        await firstSaveGate.waitUntilEntered()
        try await service.save(second)
        await firstSaveGate.open()
        try await olderSave.value

        #expect(try await service.load() == second)
    }

    @Test("Stop flushes the final catalog after a delayed save")
    func stopFlushesFinalCatalog() async throws {
        let firstRoot = temporaryDirectory("flush-first")
        let secondRoot = temporaryDirectory("flush-second")
        try FileManager.default.createDirectory(at: firstRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondRoot, withIntermediateDirectories: true)
        let fileURL = temporaryDirectory("flush-state").appendingPathComponent("state.json")
        let firstSaveGate = TestGate()
        let persistence = WorkspacePersistenceService(
            fileURL: fileURL,
            beforeSave: { revision, _ in
                if revision == 1 { await firstSaveGate.wait() }
            }
        )
        let model = makeModel("flush", persistence: persistence)
        let first = workspaceState(firstRoot)
        let second = workspaceState(secondRoot)

        try model.openWorkspace(first)
        await firstSaveGate.waitUntilEntered()
        try model.openWorkspace(second)
        let stopTask = model.stop()
        await firstSaveGate.open()
        await stopTask.value

        let saved = try #require(try await persistence.load())
        #expect(saved.workspaces.map(\.id) == [first.id, second.id])
        #expect(saved.selectedWorkspaceID == second.id)
    }

    @Test("Responder restore policy rejects inactive owners and stale requests")
    func responderRestorePolicy() {
        #expect(WorkspaceResponderPolicy.canRestore(
            ownerWorkspaceID: "first",
            activeWorkspaceID: "first",
            capturedRevision: 4,
            currentRevision: 4
        ))
        #expect(!WorkspaceResponderPolicy.canRestore(
            ownerWorkspaceID: "first",
            activeWorkspaceID: "second",
            capturedRevision: 4,
            currentRevision: 4
        ))
        #expect(!WorkspaceResponderPolicy.canRestore(
            ownerWorkspaceID: "first",
            activeWorkspaceID: "first",
            capturedRevision: 4,
            currentRevision: 5
        ))
        #expect(!WorkspaceResponderPolicy.canRestore(
            ownerWorkspaceID: nil,
            activeWorkspaceID: "first",
            capturedRevision: 4,
            currentRevision: 4
        ))
    }

    @Test("Error recovery stays distinct from unavailable recovery")
    func errorRecoveryPresentation() throws {
        let unavailable = try #require(WorkspaceRecoveryPolicy.presentation(
            for: .unavailable("Folder moved"),
            workspaceName: "Sample"
        ))
        let error = try #require(WorkspaceRecoveryPolicy.presentation(
            for: .error("Permission denied"),
            workspaceName: "Sample"
        ))

        #expect(unavailable.systemImage == "questionmark.folder")
        #expect(unavailable.accessibilityValue == "Workspace unavailable")
        #expect(error.systemImage == "exclamationmark.triangle.fill")
        #expect(error.title == "Could not open Sample")
        #expect(error.message.contains("Permission denied"))
        #expect(error.accessibilityValue == "Workspace error")
        #expect(error != unavailable)
    }

    private func makeModel(
        _ name: String,
        persistence: WorkspacePersistenceService? = nil,
        scheduleWorkspaceRestore: @escaping @MainActor @Sendable () async -> Void = {
            await Task.yield()
        }
    ) -> AppModel {
        let stateURL = temporaryDirectory(name).appendingPathComponent("state.json")
        return AppModel(environment: AppEnvironment(
            persistence: persistence ?? WorkspacePersistenceService(fileURL: stateURL),
            makeWorkspaceAccess: { WorkspaceAccessController() },
            openFolderPanel: OpenFolderPanel(),
            windowController: WindowController(),
            scheduleWorkspaceRestore: scheduleWorkspaceRestore
        ))
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<500 {
            if condition() { return }
            await Task.yield()
        }
        Issue.record("Timed out waiting for workspace state")
    }

    private func workspaceState(_ url: URL) -> WorkspaceState {
        WorkspaceState(path: url.path, bookmark: nil, lastOpenedAt: Date(timeIntervalSince1970: 1))
    }

    private func temporaryDirectory(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("atelier-lifecycle-\(name)-\(UUID().uuidString)", isDirectory: true)
    }
}

private actor TestGate {
    private var isOpen = false
    private var hasEntered = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        hasEntered = true
        let entered = entryWaiters
        entryWaiters.removeAll()
        entered.forEach { $0.resume() }
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            releaseWaiters.append(continuation)
        }
    }

    func waitUntilEntered() async {
        guard !hasEntered else { return }
        await withCheckedContinuation { continuation in
            entryWaiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}
