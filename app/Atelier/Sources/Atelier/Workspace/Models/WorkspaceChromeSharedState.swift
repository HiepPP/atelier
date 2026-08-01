import Observation

/// Panel and sidebar-tab state shared by every workspace session in the window.
///
/// One window shows one workspace at a time, so the sidebar, the inspector, and
/// the Explorer/Git selection read as window chrome rather than as workspace
/// content. Owning them per session made each switch snap the chrome back to
/// whatever that session last had. One owner keeps every workspace in step
/// without mirroring state between sessions.
@MainActor
@Observable
final class WorkspaceChromeSharedState {
    var panels = WorkspacePanelPresentation.initial(for: .standard)
    var currentLayoutMode = WorkspaceLayoutMode.standard
    var selectedSidebarTab = WorkspaceSidebarTab.explorer

    /// True once a mounted workspace has resolved the first responsive layout.
    /// Every session runs the same breakpoint, so only the first one applies it.
    private(set) var hasAppliedInitialLayout = false
    private var pendingLayoutProfilePanels: LayoutProfilePanelState?

    var layoutProfilePanelState: LayoutProfilePanelState {
        LayoutProfilePanelState(
            showsSidebar: panels.showsSidebar,
            showsInspector: panels.showsInspector,
            restoresSidebarAfterInspector: panels.restoresSidebarAfterInspector,
            selectedSidebarTab: selectedSidebarTab
        )
    }

    func applyInitialLayout(_ layout: WorkspaceLayoutMode) {
        guard !hasAppliedInitialLayout else { return }
        hasAppliedInitialLayout = true
        currentLayoutMode = layout
        guard let pendingLayoutProfilePanels else {
            panels = .initial(for: layout)
            return
        }
        selectedSidebarTab = pendingLayoutProfilePanels.selectedSidebarTab
        panels = pendingLayoutProfilePanels.presentation(for: layout)
        self.pendingLayoutProfilePanels = nil
    }

    /// Adopt a layout profile's panel preference. Before the first mounted
    /// workspace resolves its layout there is no layout mode to reconcile
    /// against, so the preference waits for `applyInitialLayout`.
    func applyLayoutProfilePanels(_ nextPanels: LayoutProfilePanelState) {
        selectedSidebarTab = nextPanels.selectedSidebarTab
        guard hasAppliedInitialLayout else {
            pendingLayoutProfilePanels = nextPanels
            return
        }
        panels = nextPanels.presentation(for: currentLayoutMode)
    }
}
