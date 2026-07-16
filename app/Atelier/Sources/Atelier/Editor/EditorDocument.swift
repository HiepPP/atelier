import Foundation

nonisolated struct EditorDocument: Identifiable, Equatable, Sendable {
    let url: URL

    var id: URL { url.standardizedFileURL }
    var displayName: String { url.lastPathComponent }
}

@MainActor
protocol EditorSurface: AnyObject {
    var document: EditorDocument? { get }

    func open(_ document: EditorDocument)
    func save() async throws
    func reveal(line: Int, column: Int)
    func focus()
}
