import Foundation
import Testing
@testable import Atelier

@Suite("Intent guard policy")
struct IntentGuardPolicyTests {
    @Test("Empty or whitespace intent is inactive")
    func activeIntent() {
        #expect(!IntentGuardPolicy.isActive(intent: ""))
        #expect(!IntentGuardPolicy.isActive(intent: "   \n\t"))
        #expect(IntentGuardPolicy.isActive(intent: "add caching"))
    }

    @Test("Dismiss suppresses until the changed-file set moves on")
    func dismissLifecycle() {
        let a = IntentGuardPolicy.signature(for: ["A.swift", "B.swift"])
        #expect(IntentGuardPolicy.isSuppressed(signature: a, dismissedSignature: a))
        #expect(IntentGuardPolicy.liftedDismissal(current: a, dismissed: a) == a)

        let b = IntentGuardPolicy.signature(for: ["A.swift", "C.swift"])
        #expect(IntentGuardPolicy.liftedDismissal(current: b, dismissed: a) == nil)
        #expect(!IntentGuardPolicy.isSuppressed(signature: b, dismissedSignature: nil))
    }

    @Test("Change volume parses the diff-stat summary line")
    func changeVolume() {
        let stat = " 3 files changed, 42 insertions(+), 7 deletions(-)\n"
        #expect(IntentGuardPolicy.changeVolume(fromDiffStat: stat) == 49)
        #expect(IntentGuardPolicy.changeVolume(fromDiffStat: "") == 0)
    }

    @Test("NONE and empty responses flag nothing")
    func parseNone() {
        let files = ["Sources/Cache.swift", "Sources/Login.swift"]
        #expect(IntentGuardPolicy.parseOutOfScope(response: "NONE", changedFiles: files) == [])
        #expect(IntentGuardPolicy.parseOutOfScope(response: "None.\n", changedFiles: files) == [])
        #expect(IntentGuardPolicy.parseOutOfScope(response: "   ", changedFiles: files) == [])
    }

    @Test("A bullet-prefixed echoed path is flagged, preserving order")
    func parseEchoedPath() {
        let files = ["Sources/Cache.swift", "Sources/Login.swift"]
        let flagged = IntentGuardPolicy.parseOutOfScope(
            response: "- Sources/Login.swift", changedFiles: files)
        #expect(flagged == ["Sources/Login.swift"])
    }

    @Test("A longer path echoed does not flag a shorter path by substring")
    func parseAvoidsSubstringCollision() {
        let files = ["Package.swift", "Vendor/Luminare/Package.swift"]
        let flagged = IntentGuardPolicy.parseOutOfScope(
            response: "Vendor/Luminare/Package.swift", changedFiles: files)
        #expect(flagged == ["Vendor/Luminare/Package.swift"])
    }
}
