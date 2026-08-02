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

    @Test("Chrome probe reports the panels every mounted workspace reads")
    func chromeProbeReportsSharedPanels() async throws {
        #expect(RuntimeProbeCommand(rawValue: "chrome") == .chrome)
        let first = temporaryChromeDirectory("chrome-probe-a")
        let second = temporaryChromeDirectory("chrome-probe-b")
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        let model = AppModel(environment: AppEnvironment(
            persistence: WorkspacePersistenceService(
                fileURL: temporaryChromeDirectory("chrome-probe-state")
                    .appendingPathComponent("state.json")
            ),
            makeWorkspaceAccess: { WorkspaceAccessController() },
            openFolderPanel: OpenFolderPanel(),
            windowController: WindowController()
        ))
        defer { model.stop() }

        try model.openWorkspace(
            WorkspaceState(path: first.path, bookmark: nil, lastOpenedAt: .now)
        )
        try model.openWorkspace(
            WorkspaceState(path: second.path, bookmark: nil, lastOpenedAt: .now)
        )
        model.chromeShared.applyInitialLayout(.wide)
        model.chromeShared.selectedSidebarTab = .sourceControl

        let response = await model.handleRuntimeProbe(
            RuntimeProbeRequest(
                schemaVersion: 1,
                id: UUID(),
                command: .chrome,
                arguments: [:],
                requestedAt: "2026-08-02T00:00:00Z"
            )
        )

        #expect(response.status == "ok")
        #expect(response.result["selectedSidebarTab"] == .string("Git"))
        #expect(response.result["layoutMode"] == .string("wide"))
        #expect(response.result["hasAppliedInitialLayout"] == .boolean(true))
        #expect(response.result["sessionCount"] == .integer(2))
        #expect(response.result["sessionsInSync"] == .boolean(true))
        #expect(
            response.result["showsSidebar"]
                == .boolean(model.chromeShared.panels.showsSidebar)
        )
        #expect(
            response.result["showsInspector"]
                == .boolean(model.chromeShared.panels.showsInspector)
        )
    }

    private func temporaryChromeDirectory(_ name: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("atelier-\(name)-\(UUID().uuidString)", isDirectory: true)
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
