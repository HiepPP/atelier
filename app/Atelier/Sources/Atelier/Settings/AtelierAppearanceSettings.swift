import CoreGraphics
import Foundation
import Observation

/// Pure appearance rules and the settings keys that back them. Kept off the
/// main actor so the clamping math stays testable without a hop.
nonisolated enum AtelierAppearancePolicy {
    static let minimumTextScale: CGFloat = 0.8
    static let maximumTextScale: CGFloat = 1.6
    static let textScaleStep: CGFloat = 0.05
    static let defaultTextScale: CGFloat = 1

    static let appTextScaleKey = "atelier.appTextScale"
    static let terminalTextScaleKey = "atelier.terminalTextScale"
    static let editorTextScaleKey = "atelier.editorTextScale"
    static let manualZoomByDisplayKey = "atelier.manualZoomByDisplay.v1"
    static let codeLigaturesKey = "atelier.codeLigaturesEnabled"
    static let menuBarExtraKey = "atelier.showsMenuBarExtra"

    /// Clamp to the range, snap to the step grid, then round to two decimals so
    /// repeated step addition cannot drift in binary floating point.
    static func clampedTextScale(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return defaultTextScale }
        let bounded = min(max(value, minimumTextScale), maximumTextScale)
        let steps = (bounded / textScaleStep).rounded()
        return (steps * textScaleStep * 100).rounded() / 100
    }

    static func percentLabel(_ scale: CGFloat) -> String {
        "\(Int((scale * 100).rounded()))%"
    }
}

/// Owner of the two appearance flags that are not scale math. Scale math stays
/// in `AtelierZoomModel`, so there is still one owner per concern.
@MainActor
@Observable
final class AtelierAppearanceModel {
    /// A change here invalidates every cached code font, so the revision lets
    /// font consumers rebuild once instead of polling the flag.
    var codeLigaturesEnabled: Bool {
        didSet {
            guard codeLigaturesEnabled != oldValue else { return }
            defaults.set(codeLigaturesEnabled, forKey: AtelierAppearancePolicy.codeLigaturesKey)
            AtelierTypography.setCodeFontLigatures(codeLigaturesEnabled)
            codeFontRevision += 1
        }
    }

    var showsMenuBarExtra: Bool {
        didSet {
            guard showsMenuBarExtra != oldValue else { return }
            defaults.set(showsMenuBarExtra, forKey: AtelierAppearancePolicy.menuBarExtraKey)
        }
    }

    private(set) var codeFontRevision = 0

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        codeLigaturesEnabled = defaults.object(
            forKey: AtelierAppearancePolicy.codeLigaturesKey
        ) as? Bool ?? true
        showsMenuBarExtra = defaults.object(
            forKey: AtelierAppearancePolicy.menuBarExtraKey
        ) as? Bool ?? true
        // An assignment inside `init` skips `didSet`, so a stored `false` would
        // otherwise never reach typography until the user toggled the switch.
        AtelierTypography.setCodeFontLigatures(codeLigaturesEnabled)
    }
}
