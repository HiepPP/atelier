import Foundation
import Testing
@testable import Atelier

@Suite("Atelier palette presentation")
@MainActor
struct AtelierPalettePresentationTests {
    @Test("Command mode keeps stable registry order and availability")
    func commandMode() {
        let model = AtelierPaletteModel()
        let context = actionContext(hasWorkspace: false)

        model.showCommands(context: context)

        #expect(model.isPresented)
        #expect(model.mode == .commands)
        #expect(model.commandResults.map(\.descriptor.id) == AtelierActionID.allCases)
        #expect(model.commandResults.first?.descriptor.id == .openFolder)
        #expect(model.commandResults.first?.isEnabled == true)
        #expect(model.commandResults.first { $0.descriptor.id == .newTerminal }?.isEnabled == false)
        #expect(model.commandResults.first { $0.descriptor.id == .navigateBack }?.isEnabled == false)
        #expect(model.commandResults.first { $0.descriptor.id == .navigateForward }?.isEnabled == true)
        #expect(model.commandResults.first { $0.descriptor.id == .reopenClosedTab }?.isEnabled == false)
        #expect(model.selection == .action(.openFolder))
    }

    @Test("Command filtering preserves a surviving selection")
    func commandFiltering() {
        let model = AtelierPaletteModel()
        let context = actionContext(hasWorkspace: true)
        model.showCommands(context: context)
        model.select(id: AtelierActionID.zoomIn.rawValue)

        model.updateQuery("zoom", actionContext: context)

        #expect(model.commandResults.map(\.descriptor.id) == [.zoomIn, .zoomOut])
        #expect(model.selection == .action(.zoomIn))
    }

    @Test("Disabled command selection cannot activate")
    func disabledCommand() {
        let model = AtelierPaletteModel()
        model.showCommands(context: actionContext(hasWorkspace: false))
        model.select(id: AtelierActionID.newTerminal.rawValue)

        #expect(model.selection == nil)

        model.showCommands(context: actionContext(hasWorkspace: false))

        #expect(model.selection == .action(.openFolder))
    }

    @Test("File mode moves selection and dismisses cleanly")
    func fileSelectionAndDismissal() async {
        let root = URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        let first = AtelierFileCandidate(
            url: root.appendingPathComponent("First.swift"),
            relativePath: "First.swift"
        )
        let second = AtelierFileCandidate(
            url: root.appendingPathComponent("Second.swift"),
            relativePath: "Second.swift"
        )
        let model = AtelierPaletteModel(fileIndex: ImmediateFileIndex([first, second]))

        model.showFiles(revision: 0)
        model.updateQuery("swift")
        await model.settleSearch()
        let initialSelection = model.selection
        model.moveSelection(by: 1)

        #expect(model.isPresented)
        #expect(initialSelection != model.selection)
        model.dismiss()
        #expect(!model.isPresented)
        #expect(model.query.isEmpty)
    }

    private func actionContext(hasWorkspace: Bool) -> AtelierActionContext {
        AtelierActionContext(
            hasWorkspace: hasWorkspace,
            canCloseWorkspace: hasWorkspace,
            canCloseTab: hasWorkspace,
            canNavigateBack: false,
            canNavigateForward: true,
            canReopenClosedTab: false,
            canZoomIn: true,
            canZoomOut: true,
            isFocusMode: false
        )
    }
}

private actor ImmediateFileIndex: WorkspaceFileIndexing {
    let values: [AtelierFileCandidate]

    init(_ values: [AtelierFileCandidate]) {
        self.values = values
    }

    func candidates(revision: Int) -> [AtelierFileCandidate] {
        values
    }
}
