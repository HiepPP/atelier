import Foundation
import Testing
@testable import Atelier

@Suite("Claude briefing")
@MainActor
struct ClaudeBriefingModelTests {
    private func makeServices(
        background: @escaping @Sendable (String) async throws -> String
    ) -> SidecarServices {
        SidecarServices(
            currentContext: {
                GemmaSidecarTabContext(
                    kind: .terminal,
                    title: "zsh",
                    status: "running",
                    systemImage: "terminal"
                )
            },
            runBackground: background,
            runInteractive: { _ in },
            readTerminalOutput: { _ in "tail" },
            unstagedDiff: { "" },
            changedFiles: { [] },
            diffStat: { "" },
            pasteIntoTerminal: { _ in false },
            isOllamaConfigured: { true }
        )
    }

    @Test("A preempted generate returns to idle and releases the guard")
    func preemptedGenerateReturnsToIdle() async {
        let model = ClaudeBriefingModel(
            services: makeServices { _ in throw CancellationError() }
        )
        model.generate()
        #expect(model.phase == .generating)
        while model.phase == .generating { await Task.yield() }
        #expect(model.phase == .idle)
        // The single-flight guard released: a new generate starts a new run.
        model.generate()
        #expect(model.phase == .generating)
    }

    @Test("A successful generate publishes the briefing")
    func generatePublishes() async {
        let model = ClaudeBriefingModel(services: makeServices { _ in "handoff prompt" })
        model.generate()
        while model.phase == .generating { await Task.yield() }
        #expect(model.phase == .ready("handoff prompt"))
    }
}
