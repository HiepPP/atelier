import AppKit
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
        #expect(AtelierMetrics.workspaceRailWidth == 176)
        #expect(AtelierMetrics.workspaceRailItemHeight == 44)
        #expect(AtelierMetrics.workspaceRailItemGap == 4)
        #expect(AtelierMetrics.projectMenuWidth == 420)
        #expect(AtelierMetrics.workspaceRailWidth == WorkspaceRailPolicy.railWidth)
        #expect(WorkspaceRailPolicy.contentWidth(containerWidth: 760) == 584)
        #expect(WorkspaceRailPolicy.contentWidth(containerWidth: 1_440) == 1_264)
        #expect(AtelierTypography.micro == 11)
        #expect(AtelierTypography.caption == 11)
        #expect(AtelierTypography.uiSize == 13)
        #expect(AtelierTypography.codeFontFamily == "JetBrains Mono")
        #expect(AtelierTypography.codeFontWeight == .regular)
        #expect(AtelierTypography.codeFontLigaturesEnabled)
        #expect(AtelierTypography.editorSize == 16)
        #expect(AtelierTypography.terminalSize == 20)
        #expect(AtelierZoomModel.baseMinimumSize == CGSize(width: 760, height: 512))
    }

    @Test("Workspace rail uses readable names and numbered shortcuts")
    func workspaceRailIdentity() {
        let firstPath = "/Users/hiep/Projects/client-a/atelier"
        let secondPath = "/Users/hiep/Projects/client-b/atelier"

        #expect(WorkspaceRailIdentityPolicy.workspaceName(path: firstPath) == "atelier")
        #expect(WorkspaceRailIdentityPolicy.workspaceName(path: secondPath) == "atelier")
        #expect(WorkspaceRailShortcutPolicy.number(for: 0) == 1)
        #expect(WorkspaceRailShortcutPolicy.number(for: 8) == 9)
        #expect(WorkspaceRailShortcutPolicy.number(for: 9) == nil)
        #expect(WorkspaceRailShortcutPolicy.index(for: 1) == 0)
        #expect(WorkspaceRailShortcutPolicy.index(for: 9) == 8)
        #expect(WorkspaceRailShortcutPolicy.index(for: 0) == nil)
        #expect(WorkspaceRailShortcutPolicy.label(for: 0) == "⌘1")
        #expect(WorkspaceRailShortcutPolicy.label(for: 8) == "⌘9")
        #expect(WorkspaceRailShortcutPolicy.label(for: 9) == nil)
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

        let inspectorOnly = WorkspacePanelPresentation(
            showsSidebar: false,
            showsInspector: true,
            restoresSidebarAfterInspector: false
        )
        let hiddenFromWide = inspectorOnly.togglingAllPanels(layout: .wide)
        #expect(hiddenFromWide == compact)
        #expect(hiddenFromWide.togglingAllPanels(layout: .wide) == wide)

        let hiddenFromStandard = inspectorOnly.togglingAllPanels(layout: .standard)
        #expect(hiddenFromStandard == compact)
        #expect(hiddenFromStandard.togglingAllPanels(layout: .standard) == standard)
        #expect(compact.togglingAllPanels(layout: .compact) == compact)

        #expect(standard.adapting(from: .standard, to: .compact) == compact)
        #expect(compact.adapting(from: .compact, to: .wide) == wide)
    }

    @Test("Workspace split animation policy respects geometry and Reduce Motion")
    func workspaceSplitAnimationPolicy() {
        #expect(WorkspaceSplitAnimationPolicy.panelDuration == 0.20)
        #expect(WorkspaceSplitAnimationPolicy.panelRollDistance == 24)
        #expect(WorkspaceSplitAnimationPolicy.frameCount == 12)
        #expect(WorkspacePanelMotionEdge.leading.hiddenOffset == -24)
        #expect(WorkspacePanelMotionEdge.trailing.hiddenOffset == 24)
        #expect(
            WorkspaceSplitAnimationPolicy.animates(
                panelChanged: true,
                reduceMotion: false,
                requestsAnimation: true
            )
        )
        #expect(
            !WorkspaceSplitAnimationPolicy.animates(
                panelChanged: false,
                reduceMotion: false,
                requestsAnimation: true
            )
        )
        #expect(
            !WorkspaceSplitAnimationPolicy.animates(
                panelChanged: true,
                reduceMotion: true,
                requestsAnimation: true
            )
        )
        #expect(
            !WorkspaceSplitAnimationPolicy.animates(
                panelChanged: true,
                reduceMotion: false,
                requestsAnimation: false
            )
        )
    }

    @Test("Inspector animation request does not animate its sidebar companion")
    func inspectorAnimationRequestTargetsInspectorOnly() {
        let sidebarAnimates = WorkspaceSplitAnimationPolicy.animates(
            panelChanged: true,
            reduceMotion: false,
            requestsAnimation: false
        )
        let inspectorAnimates = WorkspaceSplitAnimationPolicy.animates(
            panelChanged: true,
            reduceMotion: false,
            requestsAnimation: true
        )

        #expect(!sidebarAnimates)
        #expect(inspectorAnimates)
    }

    @Test("Workspace side panels hold width ahead of the center pane")
    func workspaceSidePanelHoldingPriority() {
        #expect(
            WorkspaceSplitLayoutPolicy.panelCollapseBehavior == .useConstraints
        )
        #expect(
            WorkspaceSplitLayoutPolicy.sidePanelHoldingPriority.rawValue
                > NSLayoutConstraint.Priority.defaultLow.rawValue
        )
    }

    @Test("Project command menu centers against the full app window")
    func projectCommandWindowCentering() {
        #expect(
            ProjectCommandLayoutPolicy.workspaceHorizontalOffset(
                workspaceRailWidth: AtelierMetrics.workspaceRailWidth
            ) == -88
        )
        #expect(
            ProjectCommandLayoutPolicy.toolbarCorrection(
                windowWidth: 900,
                itemFrame: CGRect(x: 293, y: 0, width: 420, height: 28)
            ) == -53
        )
        #expect(
            ProjectCommandLayoutPolicy.toolbarCorrection(
                windowWidth: 900,
                itemFrame: CGRect(x: 240, y: 0, width: 420, height: 28)
            ) == 0
        )
    }

    @Test("Project command toolbar remeasures after native window resize")
    func projectCommandToolbarRemeasuresAfterWindowResize() async {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        var corrections: [CGFloat] = []
        let marker = ProjectCommandToolbarMarkerView(
            frame: CGRect(x: 240, y: 0, width: 420, height: 28)
        ) { correction in
            corrections.append(correction)
        }
        window.contentView?.addSubview(marker)

        await Task.yield()
        corrections.removeAll()
        marker.setFrameOrigin(CGPoint(x: 100, y: 0))
        NotificationCenter.default.post(name: NSWindow.didResizeNotification, object: window)
        for _ in 0..<4 {
            await Task.yield()
        }

        #expect(corrections.count == 1)
        #expect(corrections.first.map { abs($0) >= 0.5 } == true)
    }

    @Test("Titlebar zoom accepts only empty-background double clicks")
    func titlebarZoomInteraction() {
        #expect(WorkspaceTitlebarInteractionPolicy.shouldToggleZoom(
            clickCount: 2,
            locationY: 590,
            contentLayoutMaxY: 560,
            hitsInteractiveControl: false
        ))
        #expect(!WorkspaceTitlebarInteractionPolicy.shouldToggleZoom(
            clickCount: 1,
            locationY: 590,
            contentLayoutMaxY: 560,
            hitsInteractiveControl: false
        ))
        #expect(!WorkspaceTitlebarInteractionPolicy.shouldToggleZoom(
            clickCount: 2,
            locationY: 540,
            contentLayoutMaxY: 560,
            hitsInteractiveControl: false
        ))
        #expect(!WorkspaceTitlebarInteractionPolicy.shouldToggleZoom(
            clickCount: 2,
            locationY: 590,
            contentLayoutMaxY: 560,
            hitsInteractiveControl: true
        ))
    }
}
