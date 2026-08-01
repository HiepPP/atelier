import Foundation
import Testing
@testable import Atelier

@MainActor
@Suite("Workspace chrome shared state")
struct WorkspaceChromeSharedStateTests {
    @Test("Sessions in one window read the same panels and sidebar tab")
    func sessionsShareChrome() {
        let shared = WorkspaceChromeSharedState()
        let first = makeSession("/tmp/atelier-chrome-a", shared: shared)
        let second = makeSession("/tmp/atelier-chrome-b", shared: shared)

        first.chrome.applyInitialLayout(.standard)
        first.chrome.selectedSidebarTab = .sourceControl
        first.chrome.toggleSidebar()

        #expect(second.chrome.selectedSidebarTab == .sourceControl)
        #expect(second.chrome.panels.showsSidebar == first.chrome.panels.showsSidebar)
        #expect(second.chrome.currentLayoutMode == .standard)
    }

    @Test("A second session does not reapply the initial layout")
    func initialLayoutAppliesOnce() {
        let shared = WorkspaceChromeSharedState()
        let first = makeSession("/tmp/atelier-chrome-a", shared: shared)
        let second = makeSession("/tmp/atelier-chrome-b", shared: shared)

        first.chrome.applyInitialLayout(.standard)
        first.chrome.toggleSidebar()
        let panelsAfterToggle = first.chrome.panels

        second.chrome.applyInitialLayout(.standard)

        #expect(second.chrome.panels == panelsAfterToggle)
    }

    @Test("Only the first session adapts panels across a breakpoint")
    func breakpointAdaptsOnce() {
        let shared = WorkspaceChromeSharedState()
        let first = makeSession("/tmp/atelier-chrome-a", shared: shared)
        let second = makeSession("/tmp/atelier-chrome-b", shared: shared)

        first.chrome.applyInitialLayout(.wide)
        first.chrome.adaptPanels(from: .wide, to: .compact, isFocusMode: false)
        let panelsAfterFirstAdapt = first.chrome.panels

        second.chrome.adaptPanels(from: .wide, to: .compact, isFocusMode: false)

        #expect(second.chrome.currentLayoutMode == .compact)
        #expect(second.chrome.panels == panelsAfterFirstAdapt)
    }

    @Test("A layout profile applied before the first layout waits for it")
    func profilePanelsWaitForInitialLayout() {
        let shared = WorkspaceChromeSharedState()
        let session = makeSession("/tmp/atelier-chrome-a", shared: shared)

        shared.applyLayoutProfilePanels(
            LayoutProfilePanelState(
                showsSidebar: true,
                showsInspector: false,
                restoresSidebarAfterInspector: true,
                selectedSidebarTab: .sourceControl
            )
        )
        session.chrome.applyInitialLayout(.wide)

        #expect(session.chrome.selectedSidebarTab == .sourceControl)
        #expect(session.chrome.panels.showsSidebar)
        #expect(!session.chrome.panels.showsInspector)
    }

    @Test("Reveal requests stay with the workspace that asked for them")
    func revealRequestsStayPerSession() {
        let shared = WorkspaceChromeSharedState()
        let first = makeSession("/tmp/atelier-chrome-a", shared: shared)
        let second = makeSession("/tmp/atelier-chrome-b", shared: shared)

        first.chrome.requestExplorerReveal(URL(fileURLWithPath: "/tmp/atelier-chrome-a/file.swift"))

        #expect(first.chrome.explorerRevealRequest != nil)
        #expect(second.chrome.explorerRevealRequest == nil)
    }

    private func makeSession(_ path: String, shared: WorkspaceChromeSharedState) -> WorkspaceSession {
        WorkspaceSession(
            state: WorkspaceState(
                path: path,
                bookmark: nil,
                lastOpenedAt: Date(timeIntervalSince1970: 1)
            ),
            rootURL: URL(fileURLWithPath: path, isDirectory: true),
            chromeShared: shared
        )
    }
}
