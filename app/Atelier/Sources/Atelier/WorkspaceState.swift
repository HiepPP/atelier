import Foundation

/// Trạng thái workspace được persist ra JSON.
struct WorkspaceState: Codable, Equatable {
    var path: String
    var bookmark: Data?
    var lastOpenedAt: Date
}
