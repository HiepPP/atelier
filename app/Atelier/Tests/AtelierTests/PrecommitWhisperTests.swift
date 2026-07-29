import Foundation
import Testing
@testable import Atelier

/// A serialized stub for the sidecar background call. Holds the diff to return,
/// the canned response, the number of `runBackground` calls, and the last prompt
/// so tests can prove which diff a surviving scan used. An `actor` keeps it
/// Sendable so the read-only service closures can await it off the main actor.
actor WhisperStub {
    private(set) var callCount = 0
    private(set) var lastPrompt: String?
    private var diff: String
    let response: String

    init(diff: String, response: String) {
        self.diff = diff
        self.response = response
    }

    func setDiff(_ value: String) { diff = value }
    func currentDiff() -> String { diff }

    func run(_ prompt: String) -> String {
        callCount += 1
        lastPrompt = prompt
        return response
    }
}

/// Like `WhisperStub`, but the first `runBackground` call throws
/// `CancellationError`, matching a scan preempted by another feature's
/// serialized background run.
actor FlakyWhisperStub {
    private(set) var callCount = 0
    private let diff: String
    private let response: String

    init(diff: String, response: String) {
        self.diff = diff
        self.response = response
    }

    func currentDiff() -> String { diff }

    func run(_ prompt: String) throws -> String {
        callCount += 1
        if callCount == 1 { throw CancellationError() }
        return response
    }
}

@Suite("Pre-commit whisper")
@MainActor
struct PrecommitWhisperTests {
    // MARK: - Decision

    @Test("Empty diff clears, then skips once handled")
    func emptyDiffClearThenSkip() {
        let first = PrecommitWhisperDecision.evaluate(
            diff: "   \n\t", currentTarget: nil, lastHandled: nil)
        #expect(first.action == .clear)
        #expect(first.fingerprint == PrecommitWhisperDecision.emptyFingerprint)

        let again = PrecommitWhisperDecision.evaluate(
            diff: "", currentTarget: nil,
            lastHandled: PrecommitWhisperDecision.emptyFingerprint)
        #expect(again.action == .skip)
    }

    @Test("Changed diff scans; unchanged or in-flight diff skips")
    func changeDetection() {
        let first = PrecommitWhisperDecision.evaluate(
            diff: "+print(\"x\")", currentTarget: nil, lastHandled: nil)
        #expect(first.action == .scan)

        let alreadyHandled = PrecommitWhisperDecision.evaluate(
            diff: "+print(\"x\")", currentTarget: nil, lastHandled: first.fingerprint)
        #expect(alreadyHandled.action == .skip)

        let inFlight = PrecommitWhisperDecision.evaluate(
            diff: "+print(\"x\")", currentTarget: first.fingerprint, lastHandled: nil)
        #expect(inFlight.action == .skip)

        let changed = PrecommitWhisperDecision.evaluate(
            diff: "+print(\"y\")", currentTarget: first.fingerprint, lastHandled: nil)
        #expect(changed.action == .scan)
    }

    // MARK: - Parser

    @Test("Parser maps categories and returns nothing for NONE")
    func parseCategories() {
        #expect(PrecommitWhisperParser.parse("NONE").isEmpty)
        #expect(PrecommitWhisperParser.parse("   ").isEmpty)

        let out = """
        DEBUG_PRINT | Sources/A.swift:12 | leftover print
        TODO | Sources/B.swift:3 | new TODO added
        garbage without a pipe
        """
        let findings = PrecommitWhisperParser.parse(out)
        #expect(findings.count == 2)
        #expect(findings[0].category == .debugPrint)
        #expect(findings[0].file == "Sources/A.swift")
        #expect(findings[0].line == 12)
        #expect(findings[1].category == .todo)
    }

    // MARK: - Redaction

    @Test("Prefixed secret token is redacted to first four characters")
    func secretPrefixRedaction() {
        let findings = PrecommitWhisperParser.parse(
            "SECRET | Sources/C.swift:9 | token sk_live_1234abcd")
        #expect(findings.count == 1)
        #expect(findings[0].detail.contains("sk_l****"))
        #expect(!findings[0].detail.contains("sk_live_1234abcd"))
        #expect(!findings[0].detail.contains("1234abcd"))
    }

    @Test("Plain-word secret is redacted even without digits or a known prefix")
    func secretPlainWordRedaction() {
        let findings = PrecommitWhisperParser.parse(
            "SECRET | Sources/D.swift:2 | password = \"letmein\"")
        #expect(findings.count == 1)
        #expect(!findings[0].detail.contains("letmein"))
        #expect(findings[0].detail.contains("letm****"))
    }

    // MARK: - Model debounce + cancellation

    @Test("A changed diff triggers one scan and publishes findings")
    func scanPublishesFindings() async {
        let stub = WhisperStub(diff: "+print(\"x\")",
                               response: "DEBUG_PRINT | A.swift:3 | leftover print")
        let model = PrecommitWhisperModel(services: makeServices(stub), debounceSeconds: 0.02)
        defer { model.cleanup() }

        model.tick()
        await waitUntil { !model.findings.isEmpty }

        let count = await stub.callCount
        #expect(count == 1)
        #expect(model.findings.count == 1)
        #expect(model.findings.first?.category == .debugPrint)
    }

    @Test("A newer diff cancels the pending scan so only the newer one runs")
    func newerDiffSupersedes() async {
        let stub = WhisperStub(diff: "+print(\"AAAA\")",
                               response: "DEBUG_PRINT | A.swift:3 | leftover print")
        let model = PrecommitWhisperModel(services: makeServices(stub), debounceSeconds: 1.0)
        defer { model.cleanup() }

        model.tick()
        // Sequence on the check completing, not a wall-clock sleep: once
        // isChecking drops, the first scan is armed and its 1s debounce
        // leaves the whole window for the superseding tick.
        await waitUntil { !model.isChecking }
        await stub.setDiff("+print(\"BBBB\")")
        model.tick()

        await waitUntil { !model.findings.isEmpty }
        // Give a stale first scan a chance to (wrongly) fire before asserting once.
        try? await Task.sleep(for: .milliseconds(100))

        let count = await stub.callCount
        let prompt = await stub.lastPrompt
        #expect(count == 1)
        #expect(prompt?.contains("BBBB") == true)
        #expect(prompt?.contains("AAAA") == false)
    }

    @Test("A preempted scan releases the fingerprint so the same diff rescans")
    func preemptedScanRescans() async {
        let stub = FlakyWhisperStub(
            diff: "+print(\"x\")",
            response: "DEBUG_PRINT | A.swift:3 | leftover print"
        )
        let model = PrecommitWhisperModel(
            services: makeFlakyServices(stub),
            debounceSeconds: 0.02
        )
        defer { model.cleanup() }

        model.tick()
        // The first scan throws CancellationError (a preempting feature run).
        // Sequence on the scan fully finishing: the call happened and the
        // isScanning flag dropped again, so the catch path already ran.
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if await stub.callCount == 1, !model.isScanning { break }
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(model.findings.isEmpty)

        // Same unchanged diff: the released fingerprint allows a rescan.
        model.tick()
        await waitUntil { !model.findings.isEmpty }
        let count = await stub.callCount
        #expect(count == 2)
        #expect(model.findings.first?.category == .debugPrint)
    }

    @Test("cleanup cancels a pending scan before it can call the model")
    func cleanupCancelsPendingScan() async {
        let stub = WhisperStub(diff: "+print(\"x\")",
                               response: "DEBUG_PRINT | A.swift:3 | leftover print")
        let model = PrecommitWhisperModel(services: makeServices(stub), debounceSeconds: 1.0)

        model.tick()
        // Sequence on the check completing so cleanup provably lands while
        // the scan is still debouncing, then wait past the debounce window
        // to prove the pending scan was cancelled rather than merely slow.
        await waitUntil { !model.isChecking }
        model.cleanup()
        try? await Task.sleep(for: .milliseconds(1_300))

        let count = await stub.callCount
        #expect(count == 0)
        #expect(model.findings.isEmpty)
    }

    // MARK: - Helpers

    private func makeServices(_ stub: WhisperStub) -> SidecarServices {
        SidecarServices(
            currentContext: { nil },
            runBackground: { prompt in await stub.run(prompt) },
            runInteractive: { _ in },
            readTerminalOutput: { _ in nil },
            unstagedDiff: { await stub.currentDiff() },
            changedFiles: { [] },
            diffStat: { "" },
            pasteIntoTerminal: { _ in false },
            isOllamaConfigured: { true }
        )
    }

    private func makeFlakyServices(_ stub: FlakyWhisperStub) -> SidecarServices {
        SidecarServices(
            currentContext: { nil },
            runBackground: { prompt in try await stub.run(prompt) },
            runInteractive: { _ in },
            readTerminalOutput: { _ in nil },
            unstagedDiff: { await stub.currentDiff() },
            changedFiles: { [] },
            diffStat: { "" },
            pasteIntoTerminal: { _ in false },
            isOllamaConfigured: { true }
        )
    }

    /// Generous deadline: every async test in the package is implicitly
    /// MainActor, so under a full parallel run this loop and the model's
    /// pipeline share one serialized executor with every other test. The
    /// condition decides the pass; the timeout only bounds a hung pipeline.
    private func waitUntil(
        timeout: Double = 10.0,
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}
