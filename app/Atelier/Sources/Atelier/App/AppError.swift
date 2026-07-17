import Foundation

struct AppError: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String

    static func workspace(_ error: Error) -> AppError {
        AppError(title: "Workspace Error", message: error.localizedDescription)
    }

    static func resourceExit(_ record: ResourceExitRecord) -> AppError {
        let when = record.occurredAt.formatted(date: .abbreviated, time: .shortened)
        let title = record.reason == .memory
            ? "Atelier hit its memory limit"
            : "Atelier hit its CPU limit"
        return AppError(
            title: title,
            message: "\(record.detail)\nAtelier quit automatically at \(when) to protect your Mac."
        )
    }
}
