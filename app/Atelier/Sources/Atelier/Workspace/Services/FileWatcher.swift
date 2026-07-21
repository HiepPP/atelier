import Foundation
import CoreServices

nonisolated struct FileWatcherInvalidation: OptionSet, Sendable {
    let rawValue: UInt8

    static let workspaceContent = FileWatcherInvalidation(rawValue: 1 << 0)
    static let gitMetadata = FileWatcherInvalidation(rawValue: 1 << 1)
}

nonisolated enum FileWatcherEventPolicy {
    static func invalidation(
        paths: [String],
        rootPath: String,
        mustRescan: Bool = false
    ) -> FileWatcherInvalidation {
        if mustRescan {
            return [.workspaceContent, .gitMetadata]
        }

        var result: FileWatcherInvalidation = []
        for eventPath in paths {
            if isRelevantGitMetadata(eventPath, rootPath: rootPath) {
                result.insert(.gitMetadata)
            } else if !isGitInternal(eventPath, rootPath: rootPath),
                      !IgnoreRules.shouldIgnoreEventPath(eventPath) {
                result.insert(.workspaceContent)
            }
        }
        return result
    }

    private static func isRelevantGitMetadata(_ eventPath: String, rootPath: String) -> Bool {
        let gitRoot = rootPath.hasSuffix("/") ? "\(rootPath).git" : "\(rootPath)/.git"
        guard eventPath.hasPrefix("\(gitRoot)/") else { return false }

        var relativePath = String(eventPath.dropFirst(gitRoot.count + 1))
        if relativePath.hasSuffix(".lock") {
            relativePath.removeLast(5)
        }
        return relativePath == "index"
            || relativePath == "HEAD"
            || relativePath == "packed-refs"
            || relativePath == "refs"
            || relativePath.hasPrefix("refs/")
    }

    private static func isGitInternal(_ eventPath: String, rootPath: String) -> Bool {
        let gitRoot = rootPath.hasSuffix("/") ? "\(rootPath).git" : "\(rootPath)/.git"
        return eventPath == gitRoot || eventPath.hasPrefix("\(gitRoot)/")
    }
}

// Core Services invokes callbacks across threads. Every mutable field is protected by stateLock.
nonisolated final class FileWatcher: @unchecked Sendable {
    private let path: String
    private let onInvalidate: @MainActor @Sendable (FileWatcherInvalidation) -> Void
    private let queue = DispatchQueue(label: "app.atelier.file-watcher", qos: .utility)
    private let stateLock = NSLock()
    private var stream: FSEventStreamRef?
    private var pendingWork: DispatchWorkItem?
    private var pendingInvalidation: FileWatcherInvalidation = []
    private var generation = 0

    init(
        path: String,
        onInvalidate: @escaping @MainActor @Sendable (FileWatcherInvalidation) -> Void
    ) {
        self.path = path
        self.onInvalidate = onInvalidate
    }

    func start() {
        guard stream == nil else { return }
        stateLock.lock()
        generation += 1
        stateLock.unlock()
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
            guard let info else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            let values = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
            watcher.receive(
                paths: Array(values.prefix(count)),
                flags: Array(UnsafeBufferPointer(start: flags, count: count))
            )
        }
        guard let stream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.1,
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagUseCFTypes
                    | kFSEventStreamCreateFlagFileEvents
                    | kFSEventStreamCreateFlagWatchRoot
            )
        ) else { return }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    func stop() {
        stateLock.lock()
        generation += 1
        let work = pendingWork
        pendingWork = nil
        pendingInvalidation = []
        stateLock.unlock()
        work?.cancel()
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit {
        stop()
    }

    private func receive(paths: [String], flags: [FSEventStreamEventFlags]) {
        let rescanFlags = FSEventStreamEventFlags(
            kFSEventStreamEventFlagMustScanSubDirs
                | kFSEventStreamEventFlagUserDropped
                | kFSEventStreamEventFlagKernelDropped
                | kFSEventStreamEventFlagRootChanged
        )
        let mustRescan = flags.contains { $0 & rescanFlags != 0 }
        let invalidation = FileWatcherEventPolicy.invalidation(
            paths: paths,
            rootPath: path,
            mustRescan: mustRescan
        )
        guard !invalidation.isEmpty else { return }

        stateLock.lock()
        pendingWork?.cancel()
        pendingInvalidation.formUnion(invalidation)
        let expectedGeneration = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self,
                  let invalidation = self.takePendingInvalidation(expectedGeneration) else { return }
            let onInvalidate = self.onInvalidate
            Task { @MainActor in
                onInvalidate(invalidation)
            }
        }
        pendingWork = work
        stateLock.unlock()
        queue.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private func takePendingInvalidation(
        _ expectedGeneration: Int
    ) -> FileWatcherInvalidation? {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard generation == expectedGeneration,
              stream != nil,
              !pendingInvalidation.isEmpty else { return nil }
        let invalidation = pendingInvalidation
        pendingInvalidation = []
        pendingWork = nil
        return invalidation
    }
}
