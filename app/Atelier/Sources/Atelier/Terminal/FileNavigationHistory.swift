import Foundation

nonisolated struct FileNavigationTarget: Equatable, Sendable {
    let url: URL
    let disposition: FileTabDisposition

    init(url: URL, disposition: FileTabDisposition) {
        self.url = url.standardizedFileURL
        self.disposition = disposition
    }
}

nonisolated struct FileNavigationHistory: Sendable {
    static let limit = 100

    private(set) var current: FileNavigationTarget?
    private(set) var backward: [FileNavigationTarget] = []
    private(set) var forward: [FileNavigationTarget] = []
    private(set) var closed: [FileNavigationTarget] = []

    var canGoBack: Bool { !backward.isEmpty }
    var canGoForward: Bool { !forward.isEmpty }
    var canReopenClosed: Bool { !closed.isEmpty }

    mutating func record(_ target: FileNavigationTarget) {
        guard current != target else { return }
        if let current {
            append(current, to: &backward)
        }
        current = target
        forward.removeAll(keepingCapacity: true)
    }

    mutating func goBack() -> FileNavigationTarget? {
        guard let target = backward.popLast() else { return nil }
        if let current {
            append(current, to: &forward)
        }
        current = target
        return target
    }

    mutating func goForward() -> FileNavigationTarget? {
        guard let target = forward.popLast() else { return nil }
        if let current {
            append(current, to: &backward)
        }
        current = target
        return target
    }

    mutating func recordClosed(_ target: FileNavigationTarget) {
        guard target.disposition == .permanent else { return }
        append(target, to: &closed)
    }

    mutating func reopenClosed() -> FileNavigationTarget? {
        guard let target = closed.popLast() else { return nil }
        if current != target {
            if let current {
                append(current, to: &backward)
            }
            current = target
            forward.removeAll(keepingCapacity: true)
        }
        return target
    }

    mutating func promote(_ url: URL) {
        let standardizedURL = url.standardizedFileURL
        current = current.map { promoted($0, matching: standardizedURL) }
        backward = backward.map { promoted($0, matching: standardizedURL) }
        forward = forward.map { promoted($0, matching: standardizedURL) }
    }

    mutating func clear() {
        current = nil
        backward.removeAll(keepingCapacity: false)
        forward.removeAll(keepingCapacity: false)
        closed.removeAll(keepingCapacity: false)
    }

    mutating func removeItem(at url: URL) {
        if let current, FileTreePathPolicy.contains(current.url, within: url) {
            self.current = nil
        }
        backward.removeAll { FileTreePathPolicy.contains($0.url, within: url) }
        forward.removeAll { FileTreePathPolicy.contains($0.url, within: url) }
        closed.removeAll { FileTreePathPolicy.contains($0.url, within: url) }
    }

    private func promoted(_ target: FileNavigationTarget, matching url: URL) -> FileNavigationTarget {
        guard target.url == url else { return target }
        return FileNavigationTarget(url: target.url, disposition: .permanent)
    }

    private func append(_ target: FileNavigationTarget, to stack: inout [FileNavigationTarget]) {
        guard stack.last != target else { return }
        if stack.count == Self.limit {
            stack.removeFirst()
        }
        stack.append(target)
    }
}
