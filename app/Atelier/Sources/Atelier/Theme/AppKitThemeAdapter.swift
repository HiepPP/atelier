import AppKit

nonisolated enum AppKitThemeAdapter {
    static let chrome = color(0xE9E6DD)
    static let canvas = color(0xF5F3EE)
    static let sidebar = color(0xEEEBE3)
    static let panel = color(0xF5F3EE)
    static let raised = color(0xE5E0D3)
    static let editor = color(0xF5F3EE)
    static let code = editor
    static let tabInactive = color(0xE9E6DD)
    static let border = color(0xDEDACF)
    static let selection = color(0xE5E0D3)
    static let accent = color(0xB07B56)
    static let foreground = color(0x4C4843)
    static let secondary = color(0x8C877C)
    static let gitAdded = color(0x6E7A3D)
    static let gitModified = color(0xA07842)
    static let gitDeleted = color(0xB0593F)
    static let gitUntracked = color(0x4D8A7F)
    static let terminalBackground = editor
    static let terminalForeground = foreground

    private static func color(_ value: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
