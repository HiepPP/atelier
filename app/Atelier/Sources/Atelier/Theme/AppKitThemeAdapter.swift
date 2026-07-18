import AppKit

nonisolated enum AppKitThemeAdapter {
    static let chrome = dynamic(light: 0xF1EDE5, dark: 0x23211F)
    static let canvas = dynamic(light: 0xF6F2EA, dark: 0x191816)
    static let sidebar = dynamic(light: 0xECE7DE, dark: 0x211F1C)
    static let panel = dynamic(light: 0xFCFAF5, dark: 0x292622)
    static let raised = dynamic(light: 0xE2DCD1, dark: 0x332F2A)
    static let editor = dynamic(light: 0xFBFAF7, dark: 0x1A1917)
    static let code = editor
    static let tabInactive = dynamic(light: 0xECE7DE, dark: 0x24211E)
    static let border = dynamic(light: 0xCDC5B8, dark: 0x403B35)
    static let selection = dynamic(light: 0xE8D4C2, dark: 0x4C352A)
    static let hover = dynamic(light: 0xE2DCD1, dark: 0x37322D)
    static let pressed = dynamic(light: 0xD8D0C3, dark: 0x423B34)
    static let accent = dynamic(light: 0x935A3D, dark: 0xD39A72)
    static let accentInk = dynamic(light: 0xFFF9F2, dark: 0x21150F)
    static let foreground = NSColor.labelColor
    static let secondary = NSColor.secondaryLabelColor
    static let gitAdded = dynamic(light: 0x356B43, dark: 0x7FC58C)
    static let gitModified = dynamic(light: 0x8A5B21, dark: 0xD4A45D)
    static let gitDeleted = dynamic(light: 0xA13E37, dark: 0xE17B70)
    static let gitUntracked = dynamic(light: 0x286E68, dark: 0x63C3B8)
    static let terminalBackground = editor
    static let terminalForeground = foreground

    static func editor(usesDarkAppearance: Bool) -> NSColor {
        color(usesDarkAppearance ? 0x1A1917 : 0xFBFAF7)
    }

    static func terminalForeground(usesDarkAppearance: Bool) -> NSColor {
        color(usesDarkAppearance ? 0xE4DED5 : 0x302C28)
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
