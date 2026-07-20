import Foundation

nonisolated struct EditorDocument: Identifiable, Equatable, Sendable {
    let url: URL

    var id: URL { url.standardizedFileURL }
    var displayName: String { url.lastPathComponent }
}

enum EditorFindAction: CaseIterable, Equatable {
    case showFindInterface
    case showReplaceInterface
    case nextMatch
    case previousMatch
    case setSearchString
}

nonisolated enum EditorSelectionReferencePolicy {
    static func lineRange(in text: String, selection: NSRange) -> ClosedRange<Int>? {
        let length = text.utf16.count
        guard selection.location != NSNotFound,
              selection.location < length,
              selection.length > 0 else { return nil }
        let selectedLength = min(selection.length, length - selection.location)
        guard selectedLength > 0 else { return nil }
        let startLine = lineNumber(atUTF16Offset: selection.location, in: text)
        let endLine = lineNumber(
            atUTF16Offset: selection.location + selectedLength - 1,
            in: text
        )
        return startLine...endLine
    }

    static func reference(
        fileURL: URL,
        workspaceRootURL: URL,
        lineRange: ClosedRange<Int>
    ) -> String? {
        guard let relativePath = FileTreePathPolicy.relativePath(
            of: fileURL,
            within: workspaceRootURL
        ) else { return nil }
        return "@\(relativePath):\(lineRange.lowerBound)~\(lineRange.upperBound) "
    }

    // Counts newlines in the UTF-16 prefix without allocating a substring, so
    // selection changes on a large document stay allocation-free.
    private static func lineNumber(atUTF16Offset offset: Int, in text: String) -> Int {
        var line = 1
        var index = 0
        for unit in text.utf16 {
            if index >= offset { break }
            if unit == 0x0A { line += 1 }
            index += 1
        }
        return line
    }
}

@MainActor
protocol EditorSurface: AnyObject {
    var document: EditorDocument? { get }

    func open(_ document: EditorDocument)
    func save() async throws
    func reveal(line: Int, column: Int)
    func focus()
    func performFindAction(_ action: EditorFindAction)
}
