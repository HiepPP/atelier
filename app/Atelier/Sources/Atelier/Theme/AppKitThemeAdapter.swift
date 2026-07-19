import AppKit

nonisolated enum AppKitThemeAdapter {
    static let chrome = dynamic(light: 0xE7E3DD, dark: 0x23262A)
    static let canvas = dynamic(light: 0xDEDAD3, dark: 0x181A1D)
    static let sidebar = dynamic(light: 0xE1DED8, dark: 0x202328)
    static let panel = dynamic(light: 0xF2F0EC, dark: 0x292C30)
    static let raised = dynamic(light: 0xD4D0C9, dark: 0x34383D)
    static let editor = dynamic(light: 0xF8F7F4, dark: 0x191B1E)
    static let code = editor
    static let tabInactive = dynamic(light: 0xE5E1DB, dark: 0x25282C)
    static let border = dynamic(light: 0xBFBAB2, dark: 0x42474D)
    static let selection = dynamic(light: 0xDED1C6, dark: 0x4B3730)
    static let hover = dynamic(light: 0xD8D4CD, dark: 0x383C41)
    static let pressed = dynamic(light: 0xCCC7BF, dark: 0x44494F)
    static let accent = dynamic(light: 0xA44F32, dark: 0xD79570)
    static let accentInk = dynamic(light: 0xFFF9F2, dark: 0x21150F)
    static let workspaceRailTop = dynamic(light: 0x1D232B, dark: 0x171C22)
    static let workspaceRailBottom = dynamic(light: 0x2D3B45, dark: 0x202D35)
    static let workspaceRailSolid = dynamic(light: 0x252D35, dark: 0x1D252C)
    static let workspaceRailForeground = dynamic(light: 0xF3F1EC, dark: 0xF3F1EC)
    static let workspaceRailSecondary = dynamic(light: 0xB6BEC3, dark: 0xADB7BD)
    static let workspaceRailSelection = dynamic(light: 0x3B444C, dark: 0x343E46)
    static let workspaceRailHover = dynamic(light: 0x333C44, dark: 0x2D373F)
    static let workspaceRailPressed = dynamic(light: 0x46515A, dark: 0x404B54)
    static let workspaceRailBorder = dynamic(light: 0x59636B, dark: 0x4C575F)
    static let fileTreeForeground = dynamic(light: 0x302E2B, dark: 0xE8E4DE)
    static let foreground = NSColor.labelColor
    static let secondary = NSColor.secondaryLabelColor
    static let gitAdded = dynamic(light: 0x356B43, dark: 0x7FC58C)
    static let gitModified = dynamic(light: 0x8A5B21, dark: 0xD4A45D)
    static let gitDeleted = dynamic(light: 0xA13E37, dark: 0xE17B70)
    static let gitUntracked = dynamic(light: 0x286E68, dark: 0x63C3B8)
    static let terminalBackground = editor
    static let terminalForeground = foreground

    static func editor(usesDarkAppearance: Bool) -> NSColor {
        color(usesDarkAppearance ? 0x191B1E : 0xF8F7F4)
    }

    static func terminalForeground(usesDarkAppearance: Bool) -> NSColor {
        color(usesDarkAppearance ? 0xE8E4DE : 0x292724)
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
