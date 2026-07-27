import AppKit
import CoreGraphics
import Foundation

/// Size tier selected from a display's physical diagonal.
enum DisplaySizeTier: String, CaseIterable, Sendable {
    case compact
    case comfortable
    case large

    /// Base render scale applied before any manual zoom offset.
    var baseScale: CGFloat {
        switch self {
        case .compact: return 1.00
        case .comfortable: return 1.10
        case .large: return 1.20
        }
    }
}

/// User-facing sizing choice. Automatic derives the tier from the display.
enum DisplaySizingMode: String, CaseIterable, Codable, Sendable {
    case automatic
    case compact
    case comfortable
    case large

    var label: String {
        switch self {
        case .automatic: return "Automatic"
        case .compact: return "Compact"
        case .comfortable: return "Comfortable"
        case .large: return "Large"
        }
    }

    /// Explicit tier for a forced mode, nil when automatic.
    var forcedTier: DisplaySizeTier? {
        switch self {
        case .automatic: return nil
        case .compact: return .compact
        case .comfortable: return .comfortable
        case .large: return .large
        }
    }
}

enum DisplaySizing {
    static let settingsKey = "atelier.displaySizingMode"
    static let fallbackTier: DisplaySizeTier = .comfortable

    /// Pure tier selection from a measured diagonal in inches.
    static func tier(forDiagonalInches inches: CGFloat) -> DisplaySizeTier {
        if inches < 16 { return .compact }
        if inches < 25 { return .comfortable }
        return .large
    }

    /// Physical diagonal in inches, nil when the display reports no size.
    static func diagonalInches(for screen: NSScreen) -> CGFloat? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        let displayID = CGDirectDisplayID(number.uint32Value)
        let millimetres = CGDisplayScreenSize(displayID)
        guard millimetres.width > 0, millimetres.height > 0 else { return nil }
        let width = Double(millimetres.width)
        let height = Double(millimetres.height)
        let diagonalMM = (width * width + height * height).squareRoot()
        return CGFloat(diagonalMM / 25.4)
    }

    /// Tier for a screen using its physical size, fallback when unavailable.
    static func detectedTier(for screen: NSScreen?) -> DisplaySizeTier {
        guard let screen, let inches = diagonalInches(for: screen) else { return fallbackTier }
        return tier(forDiagonalInches: inches)
    }

    /// Stable per-display key for persisting the manual zoom offset.
    static func displayKey(for screen: NSScreen?) -> String {
        guard let screen else { return fallbackTier.rawValue }
        let name = screen.localizedName
        return name.isEmpty ? detectedTier(for: screen).rawValue : name
    }
}
