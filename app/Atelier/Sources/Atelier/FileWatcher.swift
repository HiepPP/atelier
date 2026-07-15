import Foundation
import CoreServices

final class FileWatcher {
    private let path: String
    private let onInvalidate: () -> Void
    private let queue = DispatchQueue(label: "app.atelier.file-watcher", qos: .utility)
    private let stateLock = NSLock()
    private var stream: FSEventStreamRef?
    private var pendingWork: DispatchWorkItem?
    private var generation = 0

    init(path: String, onInvalidate: @escaping () -> Void) {
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
        guard mustRescan || paths.contains(where: { !isGitInternal($0) }) else { return }

        stateLock.lock()
        pendingWork?.cancel()
        let expectedGeneration = generation
        let work = DispatchWorkItem { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.isCurrent(expectedGeneration) else { return }
                self.onInvalidate()
            }
        }
        pendingWork = work
        stateLock.unlock()
        queue.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private func isCurrent(_ expectedGeneration: Int) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return generation == expectedGeneration && stream != nil
    }

    private func isGitInternal(_ eventPath: String) -> Bool {
        eventPath == "\(path)/.git" || eventPath.contains("\(path)/.git/")
    }
}
