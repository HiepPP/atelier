import Foundation
import Testing
@testable import Atelier

@Suite("Workspace cold policy")
struct WorkspaceColdPolicyTests {
    @Test("A freshly deselected workspace waits the full timeout")
    func freshlyDeselected() {
        #expect(WorkspaceColdPolicy.delay(sinceDeselected: nil) == WorkspaceColdPolicy.idleTimeout)
        #expect(WorkspaceColdPolicy.delay(sinceDeselected: .zero) == WorkspaceColdPolicy.idleTimeout)
    }

    @Test("A partially elapsed wait keeps only the remainder")
    func partiallyElapsed() {
        #expect(WorkspaceColdPolicy.delay(sinceDeselected: .seconds(20)) == .seconds(40))
        #expect(WorkspaceColdPolicy.delay(sinceDeselected: .seconds(59)) == .seconds(1))
    }

    @Test("Reaching or passing the timeout cools now")
    func timeoutReached() {
        #expect(WorkspaceColdPolicy.delay(sinceDeselected: .seconds(60)) == .zero)
        #expect(WorkspaceColdPolicy.delay(sinceDeselected: .seconds(600)) == .zero)
    }

    @Test("A negative reading falls back to the full timeout")
    func negativeElapsed() {
        #expect(
            WorkspaceColdPolicy.delay(sinceDeselected: .seconds(-5))
                == WorkspaceColdPolicy.idleTimeout
        )
    }

    @Test("The selected workspace never cools")
    func selectedNeverCools() {
        #expect(!WorkspaceColdPolicy.shouldCool(isSelected: true, sinceDeselected: .seconds(600)))
        #expect(!WorkspaceColdPolicy.shouldCool(isSelected: false, sinceDeselected: .seconds(10)))
        #expect(WorkspaceColdPolicy.shouldCool(isSelected: false, sinceDeselected: .seconds(60)))
    }
}

@Suite("Workspace cooling")
struct WorkspaceCoolingTests {
    @Test("Cooling releases a started session and warming rehydrates it")
    func coolWarmCycle() throws {
        let root = try makeWorkspaceDirectory("cool-warm")
        let session = makeSession(root)
        session.start(agentResponsesActive: false)
        defer { session.stop() }

        #expect(!session.isCold)
        #expect(session.gemmaSidecar.isTicking)
        session.cool()
        #expect(session.isCold)
        #expect(!session.gemmaSidecar.isTicking, "a cold workspace must stop the sidecar tick")

        let revisionBeforeWarm = session.fileTreeRevision
        session.warm()
        #expect(!session.isCold)
        #expect(session.gemmaSidecar.isTicking, "warming must restart the sidecar tick")
        #expect(session.fileTreeRevision == revisionBeforeWarm + 1)
    }

    @Test("Resuming ticks does nothing for a sidecar that never started")
    func resumeWithoutStart() throws {
        let root = try makeWorkspaceDirectory("sidecar-resume")
        let session = makeSession(root)
        session.gemmaSidecar.resumeTicks()
        #expect(!session.gemmaSidecar.isTicking)
    }

    @Test("Cooling twice is idempotent and warming a warm session does nothing")
    func repeatedTransitions() throws {
        let root = try makeWorkspaceDirectory("cool-repeat")
        let session = makeSession(root)
        session.start(agentResponsesActive: false)
        defer { session.stop() }

        session.cool()
        session.cool()
        #expect(session.isCold)

        session.warm()
        let revision = session.fileTreeRevision
        session.warm()
        #expect(!session.isCold)
        #expect(session.fileTreeRevision == revision)
    }

    @Test("A session that never started stays warm")
    func coolBeforeStart() throws {
        let root = try makeWorkspaceDirectory("cool-before-start")
        let session = makeSession(root)
        session.cool()
        #expect(!session.isCold)
    }

    @Test("Stopping a cold session clears its cold state")
    func stopClearsColdState() throws {
        let root = try makeWorkspaceDirectory("cool-stop")
        let session = makeSession(root)
        session.start(agentResponsesActive: false)
        session.cool()
        session.stop()
        #expect(!session.isCold)
    }

    private func makeSession(_ root: URL) -> WorkspaceSession {
        WorkspaceSession(
            state: WorkspaceState(
                path: root.path,
                bookmark: nil,
                lastOpenedAt: Date(timeIntervalSince1970: 1)
            ),
            rootURL: root
        )
    }

    private func makeWorkspaceDirectory(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("atelier-cooling-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
