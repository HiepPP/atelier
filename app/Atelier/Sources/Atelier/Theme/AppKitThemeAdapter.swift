import AppKit

nonisolated enum AppKitThemeAdapter {
    static let chrome = NSColor(calibratedRed: 0.925, green: 0.91, blue: 0.865, alpha: 1)
    static let canvas = NSColor(calibratedRed: 0.955, green: 0.945, blue: 0.91, alpha: 1)
    static let sidebar = NSColor(calibratedRed: 0.94, green: 0.925, blue: 0.88, alpha: 1)
    static let panel = NSColor(calibratedRed: 0.965, green: 0.955, blue: 0.92, alpha: 1)
    static let raised = NSColor(calibratedRed: 0.905, green: 0.89, blue: 0.845, alpha: 1)
    static let editor = NSColor(calibratedRed: 0.985, green: 0.978, blue: 0.95, alpha: 1)
    static let code = editor
    static let tabInactive = NSColor(calibratedRed: 0.90, green: 0.885, blue: 0.84, alpha: 1)
    static let border = NSColor(calibratedRed: 0.78, green: 0.76, blue: 0.71, alpha: 0.68)
    static let selection = NSColor(calibratedRed: 0.31, green: 0.60, blue: 0.56, alpha: 0.18)
    static let accent = NSColor(calibratedRed: 0.20, green: 0.45, blue: 0.42, alpha: 1)
    static let foreground = NSColor(calibratedRed: 0.29, green: 0.28, blue: 0.26, alpha: 1)
    static let secondary = NSColor(calibratedRed: 0.45, green: 0.43, blue: 0.40, alpha: 1)
    static let terminalBackground = editor
    static let terminalForeground = foreground
}
