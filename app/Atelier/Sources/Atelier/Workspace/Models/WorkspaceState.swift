import Foundation

/// Trạng thái workspace được persist ra JSON.
nonisolated struct WorkspaceState: Codable, Equatable, Sendable, Identifiable {
    var path: String
    var bookmark: Data?
    var lastOpenedAt: Date

    var id: String {
        URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.path
    }
}
