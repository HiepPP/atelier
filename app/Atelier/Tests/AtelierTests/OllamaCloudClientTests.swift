import Foundation
import Synchronization
import Testing
@testable import Atelier

@Suite("Ollama cloud transport", .serialized)
struct OllamaCloudClientTests {
    @Test("Streams newline-delimited chat chunks")
    func streamsChunks() async throws {
        TestURLProtocol.install(
            .init(
                status: 200,
                body: Data("""
                    {"model":"gemma4:cloud","message":{"role":"assistant","content":"Hello"},"done":false}
                    {"model":"gemma4:cloud","message":{"role":"assistant","content":""},"done":true}

                    """.utf8)
            )
        )
        let client = makeClient()
        let stream = await client.stream(request: request())
        var chunks: [OllamaChatChunk] = []
        for try await chunk in stream { chunks.append(chunk) }

        #expect(chunks.count == 2)
        #expect(chunks[0].message?.content == "Hello")
        #expect(chunks[1].done == true)
    }

    @Test("Maps HTTP failures without exposing large response bodies")
    func httpFailure() async {
        TestURLProtocol.install(.init(status: 503, body: Data("offline".utf8)))
        let client = makeClient()
        let stream = await client.stream(request: request())

        await #expect(throws: OllamaCloudError.httpStatus(503, "offline")) {
            for try await _ in stream {}
        }
    }

    @Test("Maps remote errors that omit the completion field")
    func remoteErrorWithoutDone() async {
        TestURLProtocol.install(
            .init(status: 200, body: Data("{\"error\":\"model unavailable\"}\n".utf8))
        )
        let client = makeClient()
        let stream = await client.stream(request: request())

        await #expect(throws: OllamaCloudError.remote("model unavailable")) {
            for try await _ in stream {}
        }
    }

    @Test("Rejects malformed and incomplete streams")
    func invalidStreams() async {
        TestURLProtocol.install(.init(status: 200, body: Data("not-json\n".utf8)))
        let malformedClient = makeClient()
        let malformed = await malformedClient.stream(request: request())
        await #expect(throws: (any Error).self) {
            for try await _ in malformed {}
        }

        TestURLProtocol.install(
            .init(
                status: 200,
                body: Data("{\"message\":{\"role\":\"assistant\",\"content\":\"partial\"},\"done\":false}\n".utf8)
            )
        )
        let incompleteClient = makeClient()
        let incomplete = await incompleteClient.stream(request: request())
        await #expect(throws: OllamaCloudError.incompleteStream) {
            for try await _ in incomplete {}
        }
    }

    @Test("Cancellation ends the active request")
    func cancellation() async throws {
        TestURLProtocol.install(.init(status: 200, body: Data(), waitsForCancellation: true))
        let client = makeClient()
        let stream = await client.stream(request: request())
        let consumer = Task {
            do {
                for try await _ in stream {}
                return false
            } catch {
                return true
            }
        }
        await Task.yield()
        await client.cancel()
        #expect(await consumer.value)
    }

    @Test("Recovery guidance matches only detected failures")
    func recoveryGuidance() {
        #expect(
            OllamaCloudError.connection("offline").recoverySuggestion ==
                "Start Ollama, then try again."
        )
        #expect(
            OllamaCloudError.httpStatus(401, "unauthorized").recoverySuggestion ==
                "Run `ollama signin`, then try again."
        )
        #expect(
            OllamaCloudError.remote("authentication required").recoverySuggestion ==
                "Run `ollama signin`, then try again."
        )
        #expect(
            OllamaCloudError.remote("model gemma4:cloud not found").recoverySuggestion ==
                "Run `ollama pull gemma4:cloud`, then try again."
        )
        #expect(OllamaCloudError.remote("service overloaded").recoverySuggestion == nil)
        #expect(OllamaCloudError.decoding("bad chunk").recoverySuggestion == nil)
    }

    private func makeClient() -> OllamaCloudClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestURLProtocol.self]
        return OllamaCloudClient(
            endpoint: URL(string: "http://atelier.test/api/chat")!,
            session: URLSession(configuration: configuration)
        )
    }

    private func request() -> OllamaChatRequest {
        OllamaChatRequest(
            messages: [OllamaChatMessage(role: .user, content: "private prompt")],
            tools: []
        )
    }
}

private nonisolated struct TestHTTPResponse: Sendable {
    let status: Int
    let body: Data
    let waitsForCancellation: Bool

    init(status: Int, body: Data, waitsForCancellation: Bool = false) {
        self.status = status
        self.body = body
        self.waitsForCancellation = waitsForCancellation
    }
}

private nonisolated final class TestURLProtocolState: Sendable {
    let response = Mutex<TestHTTPResponse?>(nil)
}

private nonisolated final class TestURLProtocol: URLProtocol {
    private static let state = TestURLProtocolState()
    private var isWaiting = false

    static func install(_ response: TestHTTPResponse) {
        state.response.withLock { $0 = response }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let response = Self.state.response.withLock({ $0 }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        let http = HTTPURLResponse(
            url: request.url!,
            statusCode: response.status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/x-ndjson"]
        )!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        if response.waitsForCancellation {
            isWaiting = true
            return
        }
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        if isWaiting {
            isWaiting = false
            client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
        }
    }
}
