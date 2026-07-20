import Foundation

nonisolated enum FileTreeServiceError: LocalizedError, Sendable {
    case read(path: String, message: String)
    case invalidName(String)
    case alreadyExists(String)
    case create(path: String, message: String)
    case rename(path: String, message: String)
    case trash(path: String, message: String)
    case gitIgnore(path: String, message: String)

    var errorDescription: String? {
        switch self {
        case .read(let path, let message):
            "Could not read \(path): \(message)"
        case .invalidName(let name):
            "\"\(name)\" is not a valid file or folder name."
        case .alreadyExists(let path):
            "An item already exists at \(path)."
        case .create(let path, let message):
            "Could not create \(path): \(message)"
        case .rename(let path, let message):
            "Could not rename \(path): \(message)"
        case .trash(let path, let message):
            "Could not move \(path) to Trash: \(message)"
        case .gitIgnore(let path, let message):
            "Could not update \(path): \(message)"
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
            let isSymbolicLink = values.isSymbolicLink == true
            let symbolicLinkTargetIsDirectory: Bool
            if isSymbolicLink {
                let targetValues = try? url.resolvingSymlinksInPath().resourceValues(
                    forKeys: [.isDirectoryKey]
                )
                symbolicLinkTargetIsDirectory = targetValues?.isDirectory == true
            } else {
                symbolicLinkTargetIsDirectory = false
            }
            return FileTreeEntry(
                url: url,
                isDirectory: values.isDirectory == true && !isSymbolicLink,
                isSymbolicLink: isSymbolicLink,
                symbolicLinkTargetIsDirectory: symbolicLinkTargetIsDirectory
            )
        }.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.url.lastPathComponent.localizedCaseInsensitiveCompare(
                $1.url.lastPathComponent
            ) == .orderedAscending
        }
    }

    func createFile(named name: String, in directory: URL) throws -> URL {
        let url = try destination(named: name, in: directory, isDirectory: false)
        do {
            try Data().write(to: url, options: .withoutOverwriting)
            return url
        } catch {
            throw FileTreeServiceError.create(
                path: url.path,
                message: error.localizedDescription
            )
        }
    }

    func createFolder(named name: String, in directory: URL) throws -> URL {
        let url = try destination(named: name, in: directory, isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: false
            )
            return url
        } catch {
            throw FileTreeServiceError.create(
                path: url.path,
                message: error.localizedDescription
            )
        }
    }

    func renameItem(at url: URL, to name: String) throws -> URL {
        let isDirectory: Bool
        do {
            isDirectory = try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
        } catch {
            throw FileTreeServiceError.rename(
                path: url.path,
                message: error.localizedDescription
            )
        }
        let destination = try destination(
            named: name,
            in: url.deletingLastPathComponent(),
            isDirectory: isDirectory
        )
        do {
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        } catch {
            throw FileTreeServiceError.rename(
                path: url.path,
                message: error.localizedDescription
            )
        }
    }

    func moveToTrash(_ url: URL) throws {
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            throw FileTreeServiceError.trash(
                path: url.path,
                message: error.localizedDescription
            )
        }
    }

    func addToGitIgnore(_ url: URL, workspaceRoot: URL) throws {
        guard let relativePath = FileTreePathPolicy.relativePath(of: url, within: workspaceRoot) else {
            throw FileTreeServiceError.gitIgnore(
                path: url.path,
                message: "The item is outside the workspace."
            )
        }
        let isDirectory: Bool
        do {
            isDirectory = try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
        } catch {
            throw FileTreeServiceError.gitIgnore(
                path: url.path,
                message: error.localizedDescription
            )
        }
        let pattern = GitIgnorePattern.pattern(
            relativePath: relativePath,
            isDirectory: isDirectory
        )
        let gitIgnoreURL = workspaceRoot.appendingPathComponent(".gitignore")

        do {
            var contents = FileManager.default.fileExists(atPath: gitIgnoreURL.path)
                ? try String(contentsOf: gitIgnoreURL, encoding: .utf8)
                : ""
            let existingPatterns = Set(
                contents.split(whereSeparator: \Character.isNewline).map(String.init)
            )
            guard !existingPatterns.contains(pattern) else { return }
            if !contents.isEmpty, !contents.hasSuffix("\n") { contents.append("\n") }
            contents.append("\(pattern)\n")
            try contents.write(to: gitIgnoreURL, atomically: true, encoding: .utf8)
        } catch {
            throw FileTreeServiceError.gitIgnore(
                path: gitIgnoreURL.path,
                message: error.localizedDescription
            )
        }
    }

    private func destination(
        named name: String,
        in directory: URL,
        isDirectory: Bool
    ) throws -> URL {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty,
              cleanName != ".",
              cleanName != "..",
              !cleanName.contains("/") else {
            throw FileTreeServiceError.invalidName(name)
        }

        let url = directory.appendingPathComponent(cleanName, isDirectory: isDirectory)
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw FileTreeServiceError.alreadyExists(url.path)
        }
        return url
    }
}
