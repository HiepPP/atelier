import Darwin
import Foundation
import Testing
@testable import Atelier

@Suite("Terminal shell reaping")
struct TerminalProcessReapTests {
    @Test("Reap escalates to SIGKILL and clears the child")
    nonisolated func reapEscalatesToKill() async throws {
        // Spawn a child that ignores the never-sent SIGTERM path entirely and
        // only dies through the SIGKILL escalation, then verify the zombie is
        // reaped: a reaped pid reports ESRCH, a lingering zombie does not.
        var pid: pid_t = 0
        var argv: [UnsafeMutablePointer<CChar>?] = [strdup("sleep"), strdup("600"), nil]
        defer { for pointer in argv { free(pointer) } }
        let spawned = posix_spawn(&pid, "/bin/sleep", nil, nil, &argv, nil)
        try #require(spawned == 0)
        try #require(pid > 0)

        TerminalProcessService.reap(shellPid: pid, killEscalationDelay: .milliseconds(200))

        var reaped = false
        for _ in 0..<200 {
            if kill(pid, 0) == -1, errno == ESRCH {
                reaped = true
                break
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(reaped)
    }

    @Test("Reap ignores invalid pids")
    func reapIgnoresInvalidPids() {
        TerminalProcessService.reap(shellPid: 0)
        TerminalProcessService.reap(shellPid: -1)
    }
}
