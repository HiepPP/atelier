import Foundation

nonisolated protocol OllamaChatStreaming: Sendable {
    func stream(request: OllamaChatRequest) async -> AsyncThrowingStream<OllamaChatChunk, Error>
    func cancel() async
}

actor OllamaCloudClient: OllamaChatStreaming {
    private let endpoint: URL
    private let session: URLSession
    private var activeTask: Task<Void, Never>?

    init(
        endpoint: URL = URL(string: "http://localhost:11434/api/chat")!,
        session: URLSession = .shared
    ) {
        self.endpoint = endpoint
        self.session = session
    }

    func stream(request: OllamaChatRequest) -> AsyncThrowingStream<OllamaChatChunk, Error> {
        activeTask?.cancel()

        let stream = AsyncThrowingStream<OllamaChatChunk, Error> { continuation in
            let task = Task { [endpoint, session] in
                do {
                    var urlRequest = URLRequest(url: endpoint)
                    urlRequest.httpMethod = "POST"
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlRequest.httpBody = try JSONEncoder().encode(request)

                    let (bytes, response) = try await session.bytes(for: urlRequest)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw OllamaCloudError.invalidResponse
                    }
                    guard (200..<300).contains(httpResponse.statusCode) else {
                        let body = try await Self.readBounded(bytes: bytes, limit: 2_048)
                        throw OllamaCloudError.httpStatus(
                            httpResponse.statusCode,
                            Self.safeErrorText(body)
                        )
                    }

                    var receivedDone = false
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            continue
                        }
                        let chunk: OllamaChatChunk
                        do {
                            chunk = try JSONDecoder().decode(
                                OllamaChatChunk.self,
                                from: Data(line.utf8)
                            )
                        } catch {
                            throw OllamaCloudError.decoding(error.localizedDescription)
                        }
                        if let remoteError = chunk.error {
                            throw OllamaCloudError.remote(Self.safeErrorText(remoteError))
                        }
                        receivedDone = receivedDone || chunk.done == true
                        continuation.yield(chunk)
                    }
                    guard receivedDone else { throw OllamaCloudError.incompleteStream }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: OllamaCloudError.cancelled)
                } catch let error as OllamaCloudError {
                    continuation.finish(throwing: error)
                } catch let error as URLError {
                    if error.code == .cancelled {
                        continuation.finish(throwing: OllamaCloudError.cancelled)
                    } else {
                        continuation.finish(
                            throwing: OllamaCloudError.connection(error.localizedDescription)
                        )
                    }
                } catch {
                    continuation.finish(
                        throwing: OllamaCloudError.connection(error.localizedDescription)
                    )
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
            activeTask = task
        }
        return stream
    }

    func cancel() {
        activeTask?.cancel()
        activeTask = nil
    }

    private nonisolated static func readBounded(
        bytes: URLSession.AsyncBytes,
        limit: Int
    ) async throws -> String {
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { break }
            data.append(byte)
        }
        return String(decoding: data, as: UTF8.self)
    }

    private nonisolated static func safeErrorText(_ text: String) -> String {
        let compact = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(compact.prefix(512))
    }
}
