import OSLog

nonisolated enum AppLogger {
    private static let subsystem = "app.atelier.Atelier"

    static let app = Logger(subsystem: subsystem, category: "App")
    static let workspace = Logger(subsystem: subsystem, category: "Workspace")
    static let fileTree = Logger(subsystem: subsystem, category: "FileTree")
    static let terminal = Logger(subsystem: subsystem, category: "Terminal")
    static let git = Logger(subsystem: subsystem, category: "Git")
    static let window = Logger(subsystem: subsystem, category: "Window")
    static let commands = Logger(subsystem: subsystem, category: "Commands")
    static let editor = Logger(subsystem: subsystem, category: "Editor")
    static let agent = Logger(subsystem: subsystem, category: "Agent")
    static let runtimeDiagnostics = Logger(subsystem: subsystem, category: "RuntimeDiagnostics")
}

nonisolated enum RuntimeSignposts {
    static let signposter = OSSignposter(
        subsystem: "app.atelier.Atelier",
        category: "RuntimeDiagnostics"
    )
}
