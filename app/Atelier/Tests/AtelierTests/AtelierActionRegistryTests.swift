import Foundation
import Testing
@testable import Atelier

@Suite("Atelier action registry")
@MainActor
struct AtelierActionRegistryTests {
    @Test("Catalog has stable unique action IDs")
    func catalogOrder() {
        let ids = AtelierActionRegistry.actions.map(\.id)

        #expect(ids == [
            .openFolder,
            .closeWorkspace,
            .newTerminal,
            .closeTab,
            .navigateBack,
            .navigateForward,
            .reopenClosedTab,
            .openGemma,
            .zoomIn,
            .zoomOut,
            .actualSize,
            .toggleFocusMode
        ])
        #expect(Set(ids).count == ids.count)
    }

    @Test("Availability follows current action context")
    func availability() {
        let empty = AtelierActionContext(
            hasWorkspace: false,
            canCloseWorkspace: false,
            canCloseTab: false,
            canNavigateBack: false,
            canNavigateForward: true,
            canReopenClosedTab: false,
            canZoomIn: true,
            canZoomOut: false,
            isFocusMode: false
        )

        #expect(AtelierActionRegistry.isEnabled(.openFolder, context: empty))
        #expect(!AtelierActionRegistry.isEnabled(.closeWorkspace, context: empty))
        #expect(!AtelierActionRegistry.isEnabled(.newTerminal, context: empty))
        #expect(!AtelierActionRegistry.isEnabled(.closeTab, context: empty))
        #expect(!AtelierActionRegistry.isEnabled(.navigateBack, context: empty))
        #expect(AtelierActionRegistry.isEnabled(.navigateForward, context: empty))
        #expect(!AtelierActionRegistry.isEnabled(.reopenClosedTab, context: empty))
        #expect(!AtelierActionRegistry.isEnabled(.openGemma, context: empty))
        #expect(AtelierActionRegistry.isEnabled(.zoomIn, context: empty))
        #expect(!AtelierActionRegistry.isEnabled(.zoomOut, context: empty))
        #expect(AtelierActionRegistry.isEnabled(.actualSize, context: empty))
        #expect(AtelierActionRegistry.isEnabled(.toggleFocusMode, context: empty))

        let unavailableSelection = AtelierActionContext(
            hasWorkspace: false,
            canCloseWorkspace: true,
            canCloseTab: false,
            canNavigateBack: false,
            canNavigateForward: false,
            canReopenClosedTab: false,
            canZoomIn: true,
            canZoomOut: true,
            isFocusMode: false
        )
        #expect(AtelierActionRegistry.isEnabled(.closeWorkspace, context: unavailableSelection))
        #expect(!AtelierActionRegistry.isEnabled(.newTerminal, context: unavailableSelection))
    }

    @Test("Focus mode title reflects current state")
    func focusModeTitle() {
        let inactive = context(isFocusMode: false)
        let active = context(isFocusMode: true)

        #expect(AtelierActionRegistry.title(for: .toggleFocusMode, context: inactive) == "Enter Focus Mode")
        #expect(AtelierActionRegistry.title(for: .toggleFocusMode, context: active) == "Exit Focus Mode")
    }

    @Test("Dispatcher routes every action to its matching handler")
    func dispatchRouting() {
        var recorded: [AtelierActionID] = []
        let handlers = AtelierActionHandlers(
            openFolder: { recorded.append(.openFolder) },
            closeWorkspace: { recorded.append(.closeWorkspace) },
            newTerminal: { recorded.append(.newTerminal) },
            closeTab: { recorded.append(.closeTab) },
            navigateBack: { recorded.append(.navigateBack) },
            navigateForward: { recorded.append(.navigateForward) },
            reopenClosedTab: { recorded.append(.reopenClosedTab) },
            openGemma: { recorded.append(.openGemma) },
            zoomIn: { recorded.append(.zoomIn) },
            zoomOut: { recorded.append(.zoomOut) },
            actualSize: { recorded.append(.actualSize) },
            toggleFocusMode: { recorded.append(.toggleFocusMode) }
        )

        for action in AtelierActionID.allCases {
            AtelierActionRegistry.perform(action, handlers: handlers)
        }

        #expect(recorded == AtelierActionID.allCases)
    }

    @Test("Live handlers resolve the active workspace at invocation time")
    func activeWorkspaceRouting() throws {
        let firstRoot = temporaryDirectory("first")
        let secondRoot = temporaryDirectory("second")
        try FileManager.default.createDirectory(at: firstRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondRoot, withIntermediateDirectories: true)
        let model = AppModel(environment: AppEnvironment(
            persistence: WorkspacePersistenceService(
                fileURL: temporaryDirectory("state").appendingPathComponent("state.json")
            ),
            makeWorkspaceAccess: { WorkspaceAccessController() },
            openFolderPanel: OpenFolderPanel(),
            windowController: WindowController()
        ))
        defer { model.stop() }

        let firstState = WorkspaceState(path: firstRoot.path, bookmark: nil, lastOpenedAt: .now)
        let secondState = WorkspaceState(path: secondRoot.path, bookmark: nil, lastOpenedAt: .now)
        try model.openWorkspace(firstState)
        let first = try #require(model.workspace)
        try model.openWorkspace(secondState)
        let second = try #require(model.workspace)

        AtelierActionRegistry.perform(.newTerminal, model: model)
        #expect(first.terminalTabs.terminalCount == 1)
        #expect(second.terminalTabs.terminalCount == 2)

        model.selectWorkspace(id: firstState.id)
        AtelierActionRegistry.perform(.newTerminal, model: model)
        #expect(first.terminalTabs.terminalCount == 2)
        #expect(second.terminalTabs.terminalCount == 2)
    }

    @Test("Close Workspace removes a selected unavailable catalog item")
    func closeUnavailableWorkspace() throws {
        let model = AppModel(environment: AppEnvironment(
            persistence: WorkspacePersistenceService(
                fileURL: temporaryDirectory("unavailable-state").appendingPathComponent("state.json")
            ),
            makeWorkspaceAccess: { WorkspaceAccessController() },
            openFolderPanel: OpenFolderPanel(),
            windowController: WindowController()
        ))
        defer { model.stop() }

        let missing = temporaryDirectory("missing")
        #expect(throws: WorkspaceAccessError.self) {
            try model.openWorkspace(
                WorkspaceState(path: missing.path, bookmark: nil, lastOpenedAt: .now)
            )
        }

        let context = AtelierActionRegistry.context(for: model)
        #expect(context.canCloseWorkspace)
        #expect(!context.hasWorkspace)
        #expect(AtelierActionRegistry.isEnabled(.closeWorkspace, context: context))

        AtelierActionRegistry.perform(.closeWorkspace, model: model)
        #expect(model.workspaceItems.isEmpty)
    }

    private func context(isFocusMode: Bool) -> AtelierActionContext {
        AtelierActionContext(
            hasWorkspace: true,
            canCloseWorkspace: true,
            canCloseTab: true,
            canNavigateBack: true,
            canNavigateForward: true,
            canReopenClosedTab: true,
            canZoomIn: true,
            canZoomOut: true,
            isFocusMode: isFocusMode
        )
    }

    private func temporaryDirectory(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("atelier-actions-\(name)-\(UUID().uuidString)", isDirectory: true)
    }
}
