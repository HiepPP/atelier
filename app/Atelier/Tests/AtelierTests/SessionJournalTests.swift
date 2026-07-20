import Foundation
import Testing
@testable import Atelier

@MainActor
private func makeServices(
    changed: [String] = [],
    stat: String = "",
    ollama: Bool = true,
    background: @escaping @Sendable (String) async throws -> String = { _ in "" }
) -> SidecarServices {
    SidecarServices(
        currentContext: { nil },
        runBackground: { prompt in try await background(prompt) },
        runInteractive: { _ in },
        readTerminalOutput: { _ in nil },
        unstagedDiff: { "" },
        changedFiles: { changed },
        diffStat: { stat },
        pasteIntoTerminal: { _ in false },
        isOllamaConfigured: { ollama }
    )
}

@MainActor
private func freshDefaults() -> UserDefaults {
    let suite = "test.sessionJournal.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite) ?? .standard
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

@Suite("Session journal")
@MainActor
struct SessionJournalTests {
    @Test("Skip when idle: no git activity produces no entry and no background call")
    func skipWhenIdle() async {
        await confirmation("runBackground not called", expectedCount: 0) { called in
            let services = makeServices(changed: [], stat: "") { _ in
                called()
                return "should not run"
            }
            let model = SessionJournalModel(
                services: services,
                interval: 100,
                defaults: freshDefaults(),
                clock: { Date() }
            )
            await model.runCycle()
            #expect(model.entries.isEmpty)
        }
    }

    @Test("Activity produces one timestamped entry")
    func entryOnActivity() async {
        let services = makeServices(changed: ["a.swift"], stat: "1 file changed") { _ in
            "Edited a.swift"
        }
        let model = SessionJournalModel(
            services: services,
            interval: 100,
            defaults: freshDefaults(),
            clock: { Date() }
        )
        await model.runCycle()
        #expect(model.entries.count == 1)
        #expect(model.entries.first?.text == "Edited a.swift")
    }

    @Test("Unchanged git state is skipped on the next cycle")
    func skipWhenUnchanged() async {
        let services = makeServices(changed: ["a.swift"], stat: "1 file changed") { _ in
            "Edited a.swift"
        }
        let model = SessionJournalModel(
            services: services,
            interval: 100,
            defaults: freshDefaults(),
            clock: { Date() }
        )
        await model.runCycle()
        await model.runCycle()
        #expect(model.entries.count == 1)
    }

    @Test("cleanup cancels an in-flight cycle and clears entries")
    func schedulerCancellation() async {
        let services = makeServices(changed: ["a.swift"], stat: "1 file changed") { _ in
            try await Task.sleep(for: .seconds(60))
            return "late entry"
        }
        var t = Date()
        let model = SessionJournalModel(
            services: services,
            interval: 100,
            defaults: freshDefaults(),
            clock: { t }
        )
        model.tick()                          // baseline
        t = t.addingTimeInterval(60)
        model.tick()                          // +60
        t = t.addingTimeInterval(60)
        model.tick()                          // +60 => 120 >= 100 -> starts a cycle
        try? await Task.sleep(for: .milliseconds(20))
        model.cleanup()                       // cancels in-flight work
        try? await Task.sleep(for: .milliseconds(20))
        #expect(model.entries.isEmpty)
    }

    @Test("Disabled toggle suppresses cycles")
    func disabledSuppresses() async {
        let defaults = freshDefaults()
        defaults.set(false, forKey: SessionJournalModel.settingsKey)
        var t = Date()
        let model = SessionJournalModel(
            services: makeServices(changed: ["a.swift"], stat: "1 file changed") { _ in "x" },
            interval: 100,
            defaults: defaults,
            clock: { t }
        )
        model.tick()
        t = t.addingTimeInterval(200)
        model.tick()                          // disabled -> accumulator reset, no cycle
        try? await Task.sleep(for: .milliseconds(20))
        #expect(model.entries.isEmpty)
    }
}
