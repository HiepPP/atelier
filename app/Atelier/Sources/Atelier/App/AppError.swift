import Foundation

struct AppError: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String

    static func workspace(_ error: Error) -> AppError {
        AppError(title: "Workspace Error", message: error.localizedDescription)
    }
}
