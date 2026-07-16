import Foundation

enum FileContent: Equatable, Sendable {
    case loading
    case text(String)
    case binary
    case tooLarge(Int)
    case error(String)

    var displayText: String {
        switch self {
        case .loading:
            return "Loading file..."
        case .text(let text):
            return text
        case .binary:
            return "Binary file. Preview is unavailable."
        case .tooLarge(let bytes):
            return "File is too large to preview (\(bytes) bytes)."
        case .error(let message):
            return "Could not read file: \(message)"
        }
    }
}

enum FileLoader {
    static let defaultLimit = 2_000_000

    static func load(url: URL, limit: Int = defaultLimit) -> FileContent {
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            guard let size = values.fileSize else {
                return .error("size is unavailable")
            }
            guard size <= limit else {
                return .tooLarge(size)
            }

            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            guard !data.prefix(8_192).contains(0) else {
                return .binary
            }
            return .text(String(decoding: data, as: UTF8.self))
        } catch {
            return .error(error.localizedDescription)
        }
    }

    static func loadAsync(url: URL, limit: Int = defaultLimit) async -> FileContent {
        await Task.detached(priority: .userInitiated) {
            load(url: url, limit: limit)
        }.value
    }
}

enum FileSaver {
    private static let queue = DispatchQueue(
        label: "app.atelier.file-saver",
        qos: .userInitiated
    )

    static func saveAsync(text: String, url: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    try Data(text.utf8).write(to: url, options: .atomic)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
