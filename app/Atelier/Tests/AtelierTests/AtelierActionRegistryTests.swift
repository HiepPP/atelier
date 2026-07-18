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
            canCloseTab: false,
            canZoomIn: true,
            canZoomOut: false,
            isFocusMode: false
        )

        #expect(AtelierActionRegistry.isEnabled(.openFolder, context: empty))
        #expect(!AtelierActionRegistry.isEnabled(.closeWorkspace, context: empty))
        #expect(!AtelierActionRegistry.isEnabled(.newTerminal, context: empty))
        #expect(!AtelierActionRegistry.isEnabled(.closeTab, context: empty))
        #expect(!AtelierActionRegistry.isEnabled(.openGemma, context: empty))
        #expect(AtelierActionRegistry.isEnabled(.zoomIn, context: empty))
        #expect(!AtelierActionRegistry.isEnabled(.zoomOut, context: empty))
        #expect(AtelierActionRegistry.isEnabled(.actualSize, context: empty))
        #expect(AtelierActionRegistry.isEnabled(.toggleFocusMode, context: empty))
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

    private func context(isFocusMode: Bool) -> AtelierActionContext {
        AtelierActionContext(
            hasWorkspace: true,
            canCloseTab: true,
            canZoomIn: true,
            canZoomOut: true,
            isFocusMode: isFocusMode
        )
    }
}
