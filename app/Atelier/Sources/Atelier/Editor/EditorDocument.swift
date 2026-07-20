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
        let source = text as NSString
        guard selection.location != NSNotFound,
              selection.location < source.length,
              selection.length > 0 else { return nil }
        let selectedLength = min(selection.length, source.length - selection.location)
        guard selectedLength > 0 else { return nil }
        let startLine = lineNumber(at: selection.location, in: source)
        let endLine = lineNumber(
            at: selection.location + selectedLength - 1,
            in: source
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

    private static func lineNumber(at utf16Offset: Int, in source: NSString) -> Int {
        source.substring(to: utf16Offset).reduce(into: 1) { line, character in
            if character == "\n" { line += 1 }
        }
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
