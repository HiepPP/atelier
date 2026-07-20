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

@MainActor
protocol EditorSurface: AnyObject {
    var document: EditorDocument? { get }

    func open(_ document: EditorDocument)
    func save() async throws
    func reveal(line: Int, column: Int)
    func focus()
    func performFindAction(_ action: EditorFindAction)
}
