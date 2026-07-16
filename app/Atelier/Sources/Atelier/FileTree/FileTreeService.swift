import Foundation

nonisolated enum FileTreeServiceError: LocalizedError, Sendable {
    case read(path: String, message: String)

    var errorDescription: String? {
        switch self {
        case .read(let path, let message):
            "Could not read \(path): \(message)"
        }
    }
}

actor FileTreeService {
    func children(of directory: URL) throws -> [FileTreeEntry] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: Array(keys),
                options: []
            )
        } catch {
            throw FileTreeServiceError.read(
                path: directory.path,
                message: error.localizedDescription
            )
        }

        return try urls.compactMap { url in
            guard !IgnoreRules.shouldIgnore(url) else { return nil }
            let values = try url.resourceValues(forKeys: keys)
            return FileTreeEntry(
                url: url,
                isDirectory: values.isDirectory == true && values.isSymbolicLink != true
            )
        }.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.url.lastPathComponent.localizedCaseInsensitiveCompare(
                $1.url.lastPathComponent
            ) == .orderedAscending
        }
    }
}
