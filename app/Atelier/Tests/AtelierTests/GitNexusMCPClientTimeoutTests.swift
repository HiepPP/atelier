import Foundation
import Synchronization
import Testing
@testable import Atelier

@Suite("GitNexus MCP timeout race")
struct GitNexusMCPClientTimeoutTests {
    @Test("Returns the operation value when it completes before the deadline")
    func operationWins() async throws {
        let value = try await GitNexusMCPClient.withTimeout(.seconds(60)) { "done" }
        #expect(value == "done")
    }

    @Test("Propagates the operation error when it fails before the deadline")
    func operationErrorPropagates() async {
        await #expect(throws: GitNexusMCPError.invalidResponse) {
            _ = try await GitNexusMCPClient.withTimeout(.seconds(60)) { () async throws -> String in
                throw GitNexusMCPError.invalidResponse
            }
        }
    }

    @Test("Times out without awaiting an operation that never completes")
    func timeoutUnwindsStalledOperation() async {
        await #expect(throws: GitNexusMCPError.timedOut) {
            _ = try await GitNexusMCPClient.withTimeout(.milliseconds(50)) { () async throws -> String in
                try await Self.stallForever()
            }
        }
    }

    @Test("Cancels the losing operation after the timeout fires")
    func timeoutCancelsLoser() async {
        let (cancellations, cancellationSource) = AsyncStream.makeStream(of: Void.self)
        await #expect(throws: GitNexusMCPError.timedOut) {
            _ = try await GitNexusMCPClient.withTimeout(.milliseconds(50)) { () async throws -> String in
                try await withTaskCancellationHandler {
                    try await Self.stallForever()
                } onCancel: {
                    cancellationSource.yield()
                }
            }
        }
        var iterator = cancellations.makeAsyncIterator()
        _ = await iterator.next()
    }

    @Test("Outer cancellation unwinds a stalled operation")
    func outerCancellationUnwinds() async {
        let task = Task {
            _ = try await GitNexusMCPClient.withTimeout(.seconds(60)) { () async throws -> String in
                try await Self.stallForever()
            }
        }
        task.cancel()
        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }

    // Retains the continuations so the deliberately stalled awaits are not
    // reported as leaked continuations by the runtime.
    private nonisolated static let stalledContinuations =
        Mutex<[CheckedContinuation<String, any Error>]>([])

    private static func stallForever() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            Self.stalledContinuations.withLock { $0.append(continuation) }
        }
    }
}
