import Foundation
import Testing
@testable import Atelier

private actor CallCounter {
    private(set) var count = 0
    func bump() { count += 1 }
}

@MainActor
private func makeServices(
    ollama: Bool = true,
    terminal: String? = "cmd not found\nexit 1",
    background: @escaping @Sendable (String) async throws -> String = { _ in "diagnosis" }
) -> SidecarServices {
    SidecarServices(
        currentContext: { nil },
        runBackground: { prompt in try await background(prompt) },
        runInteractive: { _ in },
        readTerminalOutput: { _ in terminal },
        unstagedDiff: { "" },
        changedFiles: { [] },
        diffStat: { "" },
        pasteIntoTerminal: { _ in false },
        isOllamaConfigured: { ollama }
    )
}

@MainActor
private func freshDefaults() -> UserDefaults {
    let suite = "test.terminalGuardian.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite) ?? .standard
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

@Suite("Terminal guardian")
@MainActor
struct TerminalGuardianTests {
    @Test("Zero exit code never starts a diagnosis")
    func zeroExitSkips() async {
        let counter = CallCounter()
        let model = TerminalGuardianModel(
            services: makeServices { _ in await counter.bump(); return "diag" },
            defaults: freshDefaults()
        )
        model.handleCommandFinished(exitCode: 0)
        #expect(model.isRunning == false)
        #expect(model.card == nil)
        await #expect(counter.count == 0)
    }

    @Test("Unreachable Ollama skips the diagnosis")
    func ollamaOffSkips() async {
        let counter = CallCounter()
        let model = TerminalGuardianModel(
            services: makeServices(ollama: false) { _ in await counter.bump(); return "diag" },
            defaults: freshDefaults()
        )
        model.handleCommandFinished(exitCode: 1)
        #expect(model.isRunning == false)
        await #expect(counter.count == 0)
    }

    @Test("Disabled toggle skips the diagnosis")
    func disabledSkips() async {
        let counter = CallCounter()
        let defaults = freshDefaults()
        defaults.set(false, forKey: TerminalGuardianModel.settingsKey)
        let model = TerminalGuardianModel(
            services: makeServices { _ in await counter.bump(); return "diag" },
            defaults: defaults
        )
        model.handleCommandFinished(exitCode: 1)
        #expect(model.isRunning == false)
        await #expect(counter.count == 0)
    }

    @Test("Debounce: a second failure while one run is queued is dropped")
    func debounceDropsSecond() async {
        let counter = CallCounter()
        let model = TerminalGuardianModel(
            services: makeServices { _ in await counter.bump(); return "diag" },
            defaults: freshDefaults()
        )
        // Both calls run synchronously before the scheduled Task executes, so the
        // second sees task != nil and is dropped.
        model.handleCommandFinished(exitCode: 1)
        #expect(model.isRunning == true)
        model.handleCommandFinished(exitCode: 2)
        // Let the single queued task complete.
        for _ in 0..<10 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(50))
        await #expect(counter.count == 1)
    }

    @Test("Non-zero exit publishes a diagnosis card carrying the exit code")
    func publishesCard() async {
        let model = TerminalGuardianModel(
            services: makeServices { _ in "root cause: typo" },
            defaults: freshDefaults()
        )
        model.handleCommandFinished(exitCode: 3)
        for _ in 0..<10 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(model.card?.exitCode == 3)
        #expect(model.card?.message == "root cause: typo")
        #expect(model.isRunning == false)
    }
}
