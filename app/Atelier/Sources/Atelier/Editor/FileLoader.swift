import Foundation
import UniformTypeIdentifiers

nonisolated enum FileContent: Equatable, Sendable {
    case loading
    case text(String)
    case image(Data)
    case binary
    case tooLarge(Int)
    case error(String)

    var displayText: String {
        switch self {
        case .loading:
            return "Loading file..."
        case .text(let text):
            return text
        case .image:
            return "Image preview is available in its file tab."
        case .binary:
            return "Binary file. Preview is unavailable."
        case .tooLarge(let bytes):
            return "File is too large to preview (\(bytes) bytes)."
        case .error(let message):
            return "Could not read file: \(message)"
        }
    }
}

nonisolated enum FileLoader {
    static let defaultLimit = 2_000_000
    static let defaultImageLimit = 50_000_000

    static func load(
        url: URL,
        limit: Int = defaultLimit,
        imageLimit: Int = defaultImageLimit
    ) -> FileContent {
        do {
            let values = try url.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey])
            guard let size = values.fileSize else {
                return .error("size is unavailable")
            }
            let isImage = values.contentType?.conforms(to: .image) == true
                || UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true
            guard size <= (isImage ? imageLimit : limit) else {
                return .tooLarge(size)
            }

            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            if isImage {
                return .image(data)
            }
            guard !data.prefix(8_192).contains(0) else {
                return .binary
            }
            return .text(String(decoding: data, as: UTF8.self))
        } catch {
            AppLogger.editor.error(
                "File read failed for \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return .error(error.localizedDescription)
        }
    }

    static func loadAsync(
        url: URL,
        limit: Int = defaultLimit,
        imageLimit: Int = defaultImageLimit
    ) async -> FileContent {
        await Task.detached(priority: .userInitiated) {
            load(url: url, limit: limit, imageLimit: imageLimit)
        }.value
    }
}

nonisolated enum FileSaver {
    private static let queue = DispatchQueue(
        label: "app.atelier.file-saver",
        qos: .userInitiated
    )

    /// Synchronous save for teardown paths (flush-on-close). Runs on the same
    /// serial queue as `saveAsync`, so it lands after any in-flight async
    /// write and the newest text always wins.
    static func save(text: String, url: URL) throws {
        try queue.sync {
            try Data(text.utf8).write(to: url, options: .atomic)
        }
    }

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
