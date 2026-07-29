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

/// Incrementally maintained UTF-16 line-start offsets for one document.
/// One index serves the line-number ruler, selection line math, and runtime
/// line counts, so no consumer rescans the whole document per keystroke.
nonisolated struct EditorLineIndex: Equatable, Sendable {
    /// UTF-16 offset of the first character of each logical line. Always
    /// begins with 0, so any valid offset resolves to line >= 1.
    private(set) var lineStartOffsets: [Int]
    /// UTF-16 length of the indexed text.
    private(set) var utf16Length: Int

    init(text: String = "") {
        var starts = [0]
        starts.reserveCapacity(max(1, text.utf16.count / 40))
        var offset = 0
        for unit in text.utf16 {
            offset += 1
            if unit == 0x0A {
                starts.append(offset)
            }
        }
        lineStartOffsets = starts
        utf16Length = offset
    }

    var lineCount: Int { lineStartOffsets.count }

    /// Applies one edit: `range` in the pre-edit text was replaced by
    /// `replacement`. Only the affected slice of line starts is recomputed,
    /// so cost is O(edit + shifted tail), never O(document). Returns false
    /// when the range does not fit the indexed text; the caller must then
    /// rebuild from the full new text.
    mutating func applyEdit(range: NSRange, replacement: String) -> Bool {
        guard range.location != NSNotFound,
              range.location >= 0,
              range.length >= 0,
              NSMaxRange(range) <= utf16Length else { return false }
        var insertedStarts: [Int] = []
        var offset = range.location
        for unit in replacement.utf16 {
            offset += 1
            if unit == 0x0A {
                insertedStarts.append(offset)
            }
        }
        let replacementLength = offset - range.location
        let delta = replacementLength - range.length
        // Starts at or before the edit location reference untouched text.
        let keepCount = startCount(atOrBefore: range.location)
        // Starts inside the removed span disappear; later ones shift by delta.
        let shiftFrom = startCount(atOrBefore: NSMaxRange(range))
        var rebuilt = Array(lineStartOffsets[..<keepCount])
        rebuilt.reserveCapacity(keepCount + insertedStarts.count + lineStartOffsets.count - shiftFrom)
        rebuilt.append(contentsOf: insertedStarts)
        for index in shiftFrom..<lineStartOffsets.count {
            rebuilt.append(lineStartOffsets[index] + delta)
        }
        lineStartOffsets = rebuilt
        utf16Length += delta
        return true
    }

    /// 1-based logical line containing the given UTF-16 offset.
    func lineNumber(atUTF16Offset offset: Int) -> Int {
        max(1, startCount(atOrBefore: offset))
    }

    /// Line span of a selection, matching `EditorSelectionReferencePolicy`
    /// semantics but resolved with a binary search instead of a full walk.
    func lineRange(for selection: NSRange) -> ClosedRange<Int>? {
        guard selection.location != NSNotFound,
              selection.location >= 0,
              selection.location < utf16Length,
              selection.length > 0 else { return nil }
        let selectedLength = min(selection.length, utf16Length - selection.location)
        guard selectedLength > 0 else { return nil }
        let startLine = lineNumber(atUTF16Offset: selection.location)
        let endLine = lineNumber(atUTF16Offset: selection.location + selectedLength - 1)
        return startLine...endLine
    }

    // Number of line starts <= offset (binary search upper bound).
    private func startCount(atOrBefore offset: Int) -> Int {
        var lower = 0
        var upper = lineStartOffsets.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if lineStartOffsets[middle] <= offset {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }
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
