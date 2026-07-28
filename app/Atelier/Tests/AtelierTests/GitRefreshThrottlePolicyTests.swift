import Foundation
import Testing
@testable import Atelier

@Suite("Git refresh throttle policy")
struct GitRefreshThrottlePolicyTests {
    @Test("First spawn waits only the debounce")
    func firstSpawn() {
        #expect(
            GitRefreshThrottlePolicy.delay(sinceLastSpawn: nil)
                == GitRefreshThrottlePolicy.debounce
        )
    }

    @Test("Event right after a spawn waits out the minimum spacing")
    func rightAfterSpawn() {
        #expect(
            GitRefreshThrottlePolicy.delay(sinceLastSpawn: .zero)
                == GitRefreshThrottlePolicy.minimumSpacing
        )
    }

    @Test("Burst events spaced inside the window share one trailing spawn")
    func insideWindow() {
        let delay = GitRefreshThrottlePolicy.delay(sinceLastSpawn: .milliseconds(500))
        #expect(delay == .milliseconds(1500))
    }

    @Test("Delay never drops below the debounce near the window edge")
    func nearWindowEdge() {
        let delay = GitRefreshThrottlePolicy.delay(sinceLastSpawn: .milliseconds(1900))
        #expect(delay == GitRefreshThrottlePolicy.debounce)
    }

    @Test("Quiet period past the window returns to the plain debounce")
    func pastWindow() {
        let delay = GitRefreshThrottlePolicy.delay(sinceLastSpawn: .seconds(10))
        #expect(delay == GitRefreshThrottlePolicy.debounce)
    }

    @Test("Negative elapsed time falls back to the debounce")
    func negativeElapsed() {
        let delay = GitRefreshThrottlePolicy.delay(sinceLastSpawn: .seconds(-1))
        #expect(delay == GitRefreshThrottlePolicy.debounce)
    }
}
