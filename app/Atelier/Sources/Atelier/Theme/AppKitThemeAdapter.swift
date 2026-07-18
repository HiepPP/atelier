import AppKit

nonisolated enum AppKitThemeAdapter {
    static let chrome = dynamic(light: 0xF1F3F2, dark: 0x202322)
    static let canvas = dynamic(light: 0xF7F8F7, dark: 0x181B1A)
    static let sidebar = dynamic(light: 0xEEF1EF, dark: 0x1E2120)
    static let panel = dynamic(light: 0xFFFFFF, dark: 0x242827)
    static let raised = dynamic(light: 0xE7EBE9, dark: 0x2C312F)
    static let editor = dynamic(light: 0xFAFBFA, dark: 0x181B1A)
    static let code = editor
    static let tabInactive = dynamic(light: 0xECEFED, dark: 0x202322)
    static let border = dynamic(light: 0xD9DEDC, dark: 0x353A38)
    static let selection = dynamic(light: 0xF0E4DA, dark: 0x49362A)
    static let hover = dynamic(light: 0xE5E9E7, dark: 0x2D3230)
    static let pressed = dynamic(light: 0xDCE2DF, dark: 0x353B38)
    static let accent = dynamic(light: 0xB07B56, dark: 0xD9A17C)
    static let accentInk = dynamic(light: 0x1F1712, dark: 0x1F1712)
    static let foreground = NSColor.labelColor
    static let secondary = NSColor.secondaryLabelColor
    static let gitAdded = dynamic(light: 0x397A48, dark: 0x7FC58C)
    static let gitModified = dynamic(light: 0x9A651F, dark: 0xD4A45D)
    static let gitDeleted = dynamic(light: 0xB0443A, dark: 0xE17B70)
    static let gitUntracked = dynamic(light: 0x287A73, dark: 0x63C3B8)
    static let terminalBackground = editor
    static let terminalForeground = foreground

    static func editor(usesDarkAppearance: Bool) -> NSColor {
        color(usesDarkAppearance ? 0x181B1A : 0xFAFBFA)
    }

    static func terminalForeground(usesDarkAppearance: Bool) -> NSColor {
        color(usesDarkAppearance ? 0xD8DDDA : 0x303432)
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.aqua, .darkAqua])
            return color(match == .darkAqua ? dark : light)
        }
    }

    private static func color(_ value: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
