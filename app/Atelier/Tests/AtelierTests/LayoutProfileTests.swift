import Foundation
import Testing
@testable import Atelier

@MainActor
@Suite("Layout profiles")
struct LayoutProfileTests {
    @Test("Laptop and Desktop seed fixed profile slots")
    func seededProfiles() {
        let store = LayoutProfileStore(defaults: nil)

        #expect(store.selectedID == .laptop)
        #expect(store.profiles.map(\.id) == LayoutProfileID.allCases)
        #expect(store.profile(for: .laptop).snapshot.zoom.sizingMode == .compact)
        #expect(!store.profile(for: .laptop).snapshot.panels.showsInspector)
        #expect(store.profile(for: .desktop).snapshot.zoom.sizingMode == .large)
        #expect(store.profile(for: .desktop).snapshot.panels.showsSidebar)
        #expect(store.profile(for: .desktop).snapshot.panels.showsInspector)
    }

    @Test("Manual save persists the selected slot")
    func manualSavePersists() throws {
        let suiteName = "app.atelier.tests.layout-profiles.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.set(nil, forKey: LayoutProfileStore.profilesKey)
            defaults.set(nil, forKey: LayoutProfileStore.selectedProfileKey)
        }
        let snapshot = LayoutProfileSnapshot(
            windowWidth: 1_601.2,
            windowHeight: 901.4,
            zoom: LayoutProfileZoomState(
                sizingMode: .comfortable,
                manualScale: 1.17,
                focusMode: .manual
            ),
            sidebarWidth: 401.4,
            inspectorWidth: 379.7,
            panels: LayoutProfilePanelState(
                showsSidebar: false,
                showsInspector: true,
                restoresSidebarAfterInspector: true,
                selectedSidebarTab: .sourceControl
            )
        )

        let store = LayoutProfileStore(defaults: defaults)
        store.save(snapshot, to: .desktop)
        let restored = LayoutProfileStore(defaults: defaults)

        #expect(restored.selectedID == .desktop)
        #expect(restored.profile(for: .desktop).snapshot == snapshot.normalized())
    }

    @Test("Modified state ignores subpoint geometry noise")
    func modifiedStateNormalization() {
        let store = LayoutProfileStore(defaults: nil)
        let saved = store.selectedProfile.snapshot
        var nearby = saved
        nearby.windowWidth += 0.4
        nearby.sidebarWidth += 0.4

        #expect(!store.isSelectedProfileModified(by: nearby))

        nearby.windowWidth += 1
        #expect(store.isSelectedProfileModified(by: nearby))
    }

    @Test("Saved panels reconcile with responsive layout")
    func responsivePanelReconciliation() {
        let panels = LayoutProfilePanelState(
            showsSidebar: true,
            showsInspector: true,
            restoresSidebarAfterInspector: true,
            selectedSidebarTab: .sourceControl
        )

        #expect(panels.presentation(for: .compact) == .initial(for: .compact))
        #expect(
            panels.presentation(for: .standard)
                == WorkspacePanelPresentation(
                    showsSidebar: false,
                    showsInspector: true,
                    restoresSidebarAfterInspector: true
                )
        )
        #expect(
            panels.presentation(for: .wide)
                == WorkspacePanelPresentation(
                    showsSidebar: true,
                    showsInspector: true,
                    restoresSidebarAfterInspector: true
                )
        )
    }

    @Test("Window target stays inside the current display")
    func windowTargetPolicy() {
        let target = LayoutProfileWindowPolicy.targetFrame(
            currentFrame: CGRect(x: 100, y: 100, width: 1_000, height: 700),
            currentContentSize: CGSize(width: 1_000, height: 660),
            requestedContentSize: CGSize(width: 1_720, height: 1_000),
            minimumContentSize: AtelierZoomModel.baseMinimumSize,
            visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900)
        )

        #expect(target.minX >= 0)
        #expect(target.minY >= 0)
        #expect(target.maxX <= 1_440)
        #expect(target.maxY <= 900)
        #expect(target.width == 1_440)
        #expect(target.height == 900)
    }

    @Test("Inspector width stays inside its native split range")
    func inspectorWidthPolicy() {
        #expect(
            WorkspaceInspectorWidthPolicy.clamped(100)
                == AtelierMetrics.inspectorMinWidth
        )
        #expect(
            WorkspaceInspectorWidthPolicy.clamped(900)
                == AtelierMetrics.inspectorMaxWidth
        )
        #expect(
            !WorkspaceInspectorWidthPolicy.differs(
                AtelierMetrics.inspectorIdealWidth,
                from: AtelierMetrics.inspectorIdealWidth + 0.25
            )
        )
    }
}
