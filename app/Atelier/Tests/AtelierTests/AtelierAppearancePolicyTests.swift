import CoreGraphics
import Foundation
import Testing

@testable import Atelier

@MainActor
@Suite("Atelier appearance policy")
struct AtelierAppearancePolicyTests {
    private static func makeSuite(_ label: String) throws -> (UserDefaults, String) {
        let name = "app.atelier.tests.appearance.\(label).\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        return (defaults, name)
    }

    @Test("Clamping holds both bounds and rejects unusable values")
    func clampingHoldsBounds() {
        #expect(AtelierAppearancePolicy.minimumTextScale == 0.8)
        #expect(AtelierAppearancePolicy.maximumTextScale == 1.6)
        #expect(AtelierAppearancePolicy.textScaleStep == 0.05)

        #expect(AtelierAppearancePolicy.clampedTextScale(0.5) == 0.8)
        #expect(AtelierAppearancePolicy.clampedTextScale(0.79) == 0.8)
        #expect(AtelierAppearancePolicy.clampedTextScale(1.61) == 1.6)
        #expect(AtelierAppearancePolicy.clampedTextScale(4) == 1.6)
        #expect(AtelierAppearancePolicy.clampedTextScale(.nan) == 1)
        #expect(AtelierAppearancePolicy.clampedTextScale(.infinity) == 1)
    }

    @Test("Values snap to the nearest step on the grid")
    func valuesSnapToNearestStep() {
        #expect(AtelierAppearancePolicy.clampedTextScale(1.07) == 1.05)
        #expect(AtelierAppearancePolicy.clampedTextScale(1.03) == 1.05)
        #expect(AtelierAppearancePolicy.clampedTextScale(1.02) == 1)
        #expect(AtelierAppearancePolicy.clampedTextScale(0.94) == 0.95)
        #expect(AtelierAppearancePolicy.clampedTextScale(1.15) == 1.15)
    }

    @Test("Repeated stepping stays on the grid and never drifts")
    func repeatedSteppingStaysOnGrid() {
        var scale = AtelierAppearancePolicy.defaultTextScale
        for _ in 0..<12 {
            scale = AtelierAppearancePolicy.clampedTextScale(
                scale + AtelierAppearancePolicy.textScaleStep
            )
        }
        #expect(scale == AtelierAppearancePolicy.maximumTextScale)

        for _ in 0..<20 {
            scale = AtelierAppearancePolicy.clampedTextScale(
                scale - AtelierAppearancePolicy.textScaleStep
            )
        }
        #expect(scale == AtelierAppearancePolicy.minimumTextScale)
    }

    @Test("The default text scale is 1.0 and survives a clamp unchanged")
    func defaultTextScaleSurvivesClamping() {
        let scale = AtelierAppearancePolicy.defaultTextScale
        #expect(scale == 1)
        #expect(AtelierAppearancePolicy.clampedTextScale(scale) == scale)
    }

    @Test("Percent labels round to whole percents")
    func percentLabelsRoundToWholePercents() {
        #expect(AtelierAppearancePolicy.percentLabel(1) == "100%")
        #expect(AtelierAppearancePolicy.percentLabel(1.15) == "115%")
        #expect(AtelierAppearancePolicy.percentLabel(0.8) == "80%")
        #expect(AtelierAppearancePolicy.percentLabel(1.6) == "160%")
    }

    @Test("Every settings key keeps its exact string")
    func settingsKeysKeepExactStrings() {
        #expect(AtelierAppearancePolicy.appTextScaleKey == "atelier.appTextScale")
        #expect(AtelierAppearancePolicy.terminalTextScaleKey == "atelier.terminalTextScale")
        #expect(AtelierAppearancePolicy.editorTextScaleKey == "atelier.editorTextScale")
        #expect(AtelierAppearancePolicy.manualZoomByDisplayKey == "atelier.manualZoomByDisplay.v1")
        #expect(AtelierAppearancePolicy.codeLigaturesKey == "atelier.codeLigaturesEnabled")
        #expect(AtelierAppearancePolicy.menuBarExtraKey == "atelier.showsMenuBarExtra")
    }

    @Test("An empty suite reports ligatures on and the menu bar item visible")
    func emptySuiteUsesVisibleDefaults() throws {
        let (defaults, name) = try Self.makeSuite("empty")
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }

        let model = AtelierAppearanceModel(defaults: defaults)

        #expect(model.codeLigaturesEnabled)
        #expect(model.showsMenuBarExtra)
        #expect(model.codeFontRevision == 0)
        #expect(defaults.object(forKey: AtelierAppearancePolicy.codeLigaturesKey) == nil)
        #expect(defaults.object(forKey: AtelierAppearancePolicy.menuBarExtraKey) == nil)
    }

    @Test("Turning ligatures off writes the key and reloads as false")
    func ligaturesOffPersists() throws {
        let (defaults, name) = try Self.makeSuite("ligatures")
        // `AtelierTypography` ligatures are a process-wide flag, so restore it
        // here or a parallel suite reading `codeFont` sees the flipped value.
        defer {
            AtelierTypography.setCodeFontLigatures(true)
            UserDefaults.standard.removePersistentDomain(forName: name)
        }

        let model = AtelierAppearanceModel(defaults: defaults)
        model.codeLigaturesEnabled = false

        #expect(defaults.object(forKey: AtelierAppearancePolicy.codeLigaturesKey) as? Bool == false)
        #expect(!AtelierTypography.codeFontLigaturesEnabled)
        #expect(!AtelierAppearanceModel(defaults: defaults).codeLigaturesEnabled)
    }

    @Test("The typography setter flips the flag both ways")
    func codeFontLigatureSetterRoundTrips() {
        defer { AtelierTypography.setCodeFontLigatures(true) }

        #expect(AtelierTypography.codeFontLigaturesEnabled)

        AtelierTypography.setCodeFontLigatures(false)
        #expect(!AtelierTypography.codeFontLigaturesEnabled)

        AtelierTypography.setCodeFontLigatures(true)
        #expect(AtelierTypography.codeFontLigaturesEnabled)
    }

    @Test("The code font revision advances once per real change")
    func codeFontRevisionAdvancesOncePerChange() throws {
        let (defaults, name) = try Self.makeSuite("revision")
        defer {
            AtelierTypography.setCodeFontLigatures(true)
            UserDefaults.standard.removePersistentDomain(forName: name)
        }

        let model = AtelierAppearanceModel(defaults: defaults)
        #expect(model.codeFontRevision == 0)

        model.codeLigaturesEnabled = false
        #expect(model.codeFontRevision == 1)

        model.codeLigaturesEnabled = false
        #expect(model.codeFontRevision == 1)

        model.codeLigaturesEnabled = true
        #expect(model.codeFontRevision == 2)
    }

    @Test("Hiding the menu bar item writes the key and reloads as false")
    func menuBarExtraHiddenPersists() throws {
        let (defaults, name) = try Self.makeSuite("menu-bar")
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }

        let model = AtelierAppearanceModel(defaults: defaults)
        model.showsMenuBarExtra = false

        #expect(defaults.object(forKey: AtelierAppearancePolicy.menuBarExtraKey) as? Bool == false)

        let reloaded = AtelierAppearanceModel(defaults: defaults)
        #expect(!reloaded.showsMenuBarExtra)
        #expect(reloaded.codeLigaturesEnabled)
    }

    @Test("The three text scales write their keys and reload clamped")
    func textScalesPersistPerSurface() throws {
        let (defaults, name) = try Self.makeSuite("text-scales")
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }

        let zoom = AtelierZoomModel(windowController: WindowController(), defaults: defaults)
        #expect(zoom.appTextScale == 1)
        #expect(zoom.terminalTextScale == 1)
        #expect(zoom.editorTextScale == 1)

        zoom.setAppTextScale(1.25)
        zoom.setTerminalTextScale(0.4)
        zoom.setEditorTextScale(1.4)

        #expect(zoom.appTextScale == 1.25)
        #expect(zoom.terminalTextScale == 0.8)
        #expect(zoom.editorTextScale == 1.4)
        #expect(defaults.object(forKey: AtelierAppearancePolicy.appTextScaleKey) as? Double == 1.25)
        #expect(
            defaults.object(forKey: AtelierAppearancePolicy.terminalTextScaleKey) as? Double == 0.8
        )
        #expect(
            defaults.object(forKey: AtelierAppearancePolicy.editorTextScaleKey) as? Double == 1.4
        )

        let reloaded = AtelierZoomModel(windowController: WindowController(), defaults: defaults)
        #expect(reloaded.appTextScale == 1.25)
        #expect(reloaded.terminalTextScale == 0.8)
        #expect(reloaded.editorTextScale == 1.4)
    }

    @Test("Each text scale multiplies only its own surface")
    func textScalesStayIndependent() throws {
        let (defaults, name) = try Self.makeSuite("independent")
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }

        let zoom = AtelierZoomModel(windowController: WindowController(), defaults: defaults)
        let baseContent = zoom.contentScale
        let baseTerminal = zoom.terminalScale
        let baseEditor = zoom.editorScale

        zoom.setTerminalTextScale(1.5)

        #expect(zoom.contentScale == baseContent)
        #expect(zoom.editorScale == baseEditor)
        #expect(zoom.terminalScale > baseTerminal)
    }
}
