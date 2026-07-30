import Foundation
import Synchronization
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

    @Test("A burst held for the max wait fires immediately")
    func maximumWaitReached() {
        #expect(
            GitRefreshThrottlePolicy.delay(
                sinceLastSpawn: .zero,
                sinceFirstPendingEvent: GitRefreshThrottlePolicy.maximumWait
            ) == .zero
        )
        #expect(
            GitRefreshThrottlePolicy.delay(
                sinceLastSpawn: .milliseconds(10),
                sinceFirstPendingEvent: .seconds(30)
            ) == .zero
        )
    }

    @Test("Scheduled delay never overshoots the max-wait deadline")
    func delayClampedToDeadline() {
        // Spacing alone would ask for 1.5s, but only 0.4s of max wait remains.
        let delay = GitRefreshThrottlePolicy.delay(
            sinceLastSpawn: .milliseconds(500),
            sinceFirstPendingEvent: .milliseconds(1600)
        )
        #expect(delay == .milliseconds(400))
    }

    @Test("A fresh pending window still honours spacing and debounce")
    func freshPendingWindow() {
        #expect(
            GitRefreshThrottlePolicy.delay(
                sinceLastSpawn: .zero,
                sinceFirstPendingEvent: .zero
            ) == GitRefreshThrottlePolicy.minimumSpacing
        )
        #expect(
            GitRefreshThrottlePolicy.delay(
                sinceLastSpawn: nil,
                sinceFirstPendingEvent: .zero
            ) == GitRefreshThrottlePolicy.debounce
        )
    }

    @Test("A sustained burst cannot starve the refresh")
    func sustainedBurstCannotStarve() {
        // Events every 100ms, faster than the 300ms debounce: the old pure
        // trailing debounce rescheduled forever and never spawned.
        var pending: Duration = .zero
        var firedAfter: Duration?
        for step in 0..<100 {
            pending = .milliseconds(step * 100)
            let delay = GitRefreshThrottlePolicy.delay(
                sinceLastSpawn: .milliseconds(step * 100),
                sinceFirstPendingEvent: pending
            )
            if delay == .zero {
                firedAfter = pending
                break
            }
        }
        #expect(firedAfter != nil)
        #expect(firedAfter == GitRefreshThrottlePolicy.maximumWait)
    }
}

@Suite("File watcher debounce policy")
struct FileWatcherDebouncePolicyTests {
    @Test("A fresh or unknown pending window waits the debounce")
    func freshWindow() {
        #expect(
            FileWatcherDebouncePolicy.delay(sinceFirstPendingEvent: nil)
                == FileWatcherDebouncePolicy.debounce
        )
        #expect(
            FileWatcherDebouncePolicy.delay(sinceFirstPendingEvent: .zero)
                == FileWatcherDebouncePolicy.debounce
        )
        #expect(
            FileWatcherDebouncePolicy.delay(sinceFirstPendingEvent: .seconds(-1))
                == FileWatcherDebouncePolicy.debounce
        )
    }

    @Test("Reaching the max wait delivers immediately")
    func maximumWaitReached() {
        #expect(
            FileWatcherDebouncePolicy.delay(
                sinceFirstPendingEvent: FileWatcherDebouncePolicy.maximumWait
            ) == .zero
        )
        #expect(FileWatcherDebouncePolicy.delay(sinceFirstPendingEvent: .seconds(9)) == .zero)
    }

    @Test("Delay shrinks so it never overshoots the deadline")
    func delayClampedToDeadline() {
        #expect(
            FileWatcherDebouncePolicy.delay(sinceFirstPendingEvent: .milliseconds(900))
                == .milliseconds(100)
        )
        #expect(
            FileWatcherDebouncePolicy.delay(sinceFirstPendingEvent: .milliseconds(500))
                == FileWatcherDebouncePolicy.debounce
        )
    }

    @Test("Duration converts to seconds for Dispatch deadlines")
    func secondsConversion() {
        #expect(FileWatcherDebouncePolicy.seconds(.milliseconds(200)) == 0.2)
        #expect(FileWatcherDebouncePolicy.seconds(.zero) == 0)
        #expect(FileWatcherDebouncePolicy.seconds(.seconds(1)) == 1)
    }
}

@Suite("File watcher delivery")
struct FileWatcherDeliveryTests {
    /// Writes land faster than the debounce for longer than the max wait. The
    /// pure trailing debounce cancelled and rescheduled forever here, so the
    /// workspace never learned about the burst until it ended.
    @Test("A sustained write burst delivers before the burst ends")
    @MainActor
    func sustainedBurstDelivers() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("atelier-file-watcher-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let deliveries = Mutex(0)
        let watcher = FileWatcher(path: root.path) { _ in
            deliveries.withLock { $0 += 1 }
        }
        watcher.start()
        defer { watcher.stop() }
        // FSEvents needs a moment to arm, and arming itself can deliver the
        // directory-creation event. Drain that before measuring the burst.
        try await Task.sleep(for: .milliseconds(500))
        deliveries.withLock { $0 = 0 }

        // Writes every 30ms keep FSEvents batches arriving well inside the
        // 200ms debounce, so only the max-wait bound can deliver here.
        let burstStart = ContinuousClock.now
        let burstEnd = burstStart + .seconds(3)
        var index = 0
        var delivered = 0
        while ContinuousClock.now < burstEnd, delivered == 0 {
            try Data("\(index)".utf8).write(
                to: root.appendingPathComponent("burst-\(index).txt")
            )
            index += 1
            try await Task.sleep(for: .milliseconds(30))
            delivered = deliveries.withLock { $0 }
        }
        let elapsed = ContinuousClock.now - burstStart

        #expect(delivered > 0)
        // Bound the wait generously: the point is that it fires mid-burst
        // rather than only after the writes stop.
        #expect(elapsed < .seconds(2))
    }
}
