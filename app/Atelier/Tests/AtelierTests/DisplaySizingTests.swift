import Foundation
import Testing
@testable import Atelier

@Suite("Display sizing")
struct DisplaySizingTests {
    @Test("Diagonal maps to the expected tier at boundaries")
    func tierBoundaries() {
        #expect(DisplaySizing.tier(forDiagonalInches: 13.6) == .compact)
        #expect(DisplaySizing.tier(forDiagonalInches: 15.9) == .compact)
        #expect(DisplaySizing.tier(forDiagonalInches: 16) == .comfortable)
        #expect(DisplaySizing.tier(forDiagonalInches: 24) == .comfortable)
        #expect(DisplaySizing.tier(forDiagonalInches: 24.99) == .comfortable)
        #expect(DisplaySizing.tier(forDiagonalInches: 25) == .large)
        #expect(DisplaySizing.tier(forDiagonalInches: 27) == .large)
    }

    @Test("Base scale grows with tier")
    func baseScaleOrdering() {
        #expect(DisplaySizeTier.compact.baseScale == 1.00)
        #expect(DisplaySizeTier.comfortable.baseScale == 1.10)
        #expect(DisplaySizeTier.large.baseScale == 1.20)
        #expect(DisplaySizeTier.compact.baseScale < DisplaySizeTier.comfortable.baseScale)
        #expect(DisplaySizeTier.comfortable.baseScale < DisplaySizeTier.large.baseScale)
    }

    @Test("Forced mode overrides automatic tier")
    func forcedModeTier() {
        #expect(DisplaySizingMode.automatic.forcedTier == nil)
        #expect(DisplaySizingMode.compact.forcedTier == .compact)
        #expect(DisplaySizingMode.comfortable.forcedTier == .comfortable)
        #expect(DisplaySizingMode.large.forcedTier == .large)
    }

    @Test("Mode round-trips through its raw value")
    func modeRawValue() {
        for mode in DisplaySizingMode.allCases {
            #expect(DisplaySizingMode(rawValue: mode.rawValue) == mode)
        }
    }

    @Test("Font sizes snap to whole device pixels")
    func fontSnapping() {
        // 1x display: fractional sizes round to whole points.
        #expect(AtelierFontScaling.snapped(23.75, displayScale: 1) == 24)
        #expect(AtelierFontScaling.snapped(18.05, displayScale: 1) == 18)
        // 2x display: half points survive because they land on whole device pixels.
        #expect(AtelierFontScaling.snapped(23.5, displayScale: 2) == 23.5)
        // Degenerate scale is passed through untouched.
        #expect(AtelierFontScaling.snapped(12.5, displayScale: 0) == 12.5)
    }

    @Test("Terminal smoothing stays enabled on every display")
    func terminalRenderingPolicy() {
        #expect(!TerminalRenderingPolicy.usesMetal(displayScale: 1))
        #expect(TerminalRenderingPolicy.usesMetal(displayScale: 2))
        #expect(TerminalRenderingPolicy.usesFontSmoothing(displayScale: 1))
        #expect(TerminalRenderingPolicy.usesFontSmoothing(displayScale: 2))
    }

    @Test("Workspace panes adapt around editor-first breakpoints")
    func workspaceLayoutPolicy() {
        #expect(WorkspaceLayoutPolicy.mode(containerWidth: 759) == .compact)
        #expect(WorkspaceLayoutPolicy.mode(containerWidth: 760) == .compact)
        #expect(WorkspaceLayoutPolicy.mode(containerWidth: 899) == .compact)
        #expect(WorkspaceLayoutPolicy.mode(containerWidth: 900) == .standard)
        #expect(WorkspaceLayoutPolicy.mode(containerWidth: 1_279) == .standard)
        #expect(WorkspaceLayoutPolicy.mode(containerWidth: 1_280) == .wide)

        #expect(!WorkspaceLayoutMode.compact.docksSidebar)
        #expect(WorkspaceLayoutMode.standard.docksSidebar)
        #expect(WorkspaceLayoutMode.wide.docksSidebar)
        #expect(!WorkspaceLayoutMode.compact.showsInspectorByDefault)
        #expect(!WorkspaceLayoutMode.standard.showsInspectorByDefault)
        #expect(WorkspaceLayoutMode.wide.showsInspectorByDefault)
        #expect(!WorkspaceLayoutMode.compact.supportsInspector)
        #expect(WorkspaceLayoutMode.standard.supportsInspector)
        #expect(WorkspaceLayoutMode.wide.supportsInspector)
        #expect(!WorkspaceLayoutMode.compact.keepsSidebarWithInspector)
        #expect(!WorkspaceLayoutMode.standard.keepsSidebarWithInspector)
        #expect(WorkspaceLayoutMode.wide.keepsSidebarWithInspector)

        #expect(WorkspaceSidebarTab.allCases == [.explorer, .sourceControl])

        #expect(AtelierMetrics.tabBarHeight == 34)
        #expect(AtelierMetrics.workspaceRailWidth == 56)
        #expect(AtelierMetrics.workspaceRailItemSize == 36)
        #expect(AtelierMetrics.workspaceRailItemGap == 8)
        #expect(AtelierMetrics.workspaceRailWidth == WorkspaceRailPolicy.railWidth)
        #expect(WorkspaceRailPolicy.contentWidth(containerWidth: 760) == 704)
        #expect(WorkspaceRailPolicy.contentWidth(containerWidth: 1_440) == 1_384)
        #expect(AtelierTypography.micro == 11)
        #expect(AtelierTypography.caption == 11)
        #expect(AtelierTypography.uiSize == 13)
        #expect(AtelierTypography.editorSize == 13)
        #expect(AtelierTypography.terminalSize == 14)
        #expect(AtelierZoomModel.baseMinimumSize == CGSize(width: 760, height: 512))
    }

    @Test("Workspace panel transitions stay atomic across layout modes")
    func workspacePanelTransitions() {
        let compact = WorkspacePanelPresentation.initial(for: .compact)
        let standard = WorkspacePanelPresentation.initial(for: .standard)
        let wide = WorkspacePanelPresentation.initial(for: .wide)

        #expect(!compact.showsSidebar)
        #expect(!compact.showsInspector)
        #expect(standard.showsSidebar)
        #expect(!standard.showsInspector)
        #expect(wide.showsSidebar)
        #expect(wide.showsInspector)

        let standardInspector = standard.togglingInspector(layout: .standard)
        #expect(!standardInspector.showsSidebar)
        #expect(standardInspector.showsInspector)
        #expect(standardInspector.togglingInspector(layout: .standard) == standard)
        #expect(standardInspector.togglingSidebar(layout: .standard) == standard)

        let standardFromWide = wide.adapting(from: .wide, to: .standard)
        #expect(!standardFromWide.showsSidebar)
        #expect(standardFromWide.showsInspector)
        #expect(standardFromWide.togglingInspector(layout: .standard) == standard)

        #expect(standard.adapting(from: .standard, to: .compact) == compact)
        #expect(compact.adapting(from: .compact, to: .wide) == wide)
    }
}
