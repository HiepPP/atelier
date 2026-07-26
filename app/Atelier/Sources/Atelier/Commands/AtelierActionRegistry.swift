import Foundation

nonisolated enum AtelierActionID: String, CaseIterable, Identifiable, Sendable {
    case openFolder
    case closeWorkspace
    case nextWorkspace
    case newTerminal
    case newClaudeCodeTerminal
    case newCodexTerminal
    case closeTab
    case navigateBack
    case navigateForward
    case reopenClosedTab
    case openGemma
    case showExplorer
    case showGit
    case toggleAgentResponses
    case toggleLeftPanel
    case toggleWorkspacePanels
    case toggleRightPanel
    case zoomIn
    case zoomOut
    case actualSize
    case toggleFocusMode

    var id: String { rawValue }
}

nonisolated struct AtelierActionDescriptor: Identifiable, Equatable, Sendable {
    let id: AtelierActionID
    let title: String
    let category: String
    let systemImage: String
    let shortcutLabel: String?
}

nonisolated struct AtelierActionContext: Equatable, Sendable {
    let hasWorkspace: Bool
    let canCloseWorkspace: Bool
    let canCycleWorkspaces: Bool
    let canCloseTab: Bool
    let canNavigateBack: Bool
    let canNavigateForward: Bool
    let canReopenClosedTab: Bool
    let canShowSidebarTab: Bool
    let canToggleLeftPanel: Bool
    let canToggleWorkspacePanels: Bool
    let canToggleRightPanel: Bool
    let canZoomIn: Bool
    let canZoomOut: Bool
    let isFocusMode: Bool
}

@MainActor
struct AtelierActionHandlers {
    let openFolder: () -> Void
    let closeWorkspace: () -> Void
    let nextWorkspace: () -> Void
    let newTerminal: () -> Void
    let newClaudeCodeTerminal: () -> Void
    let newCodexTerminal: () -> Void
    let closeTab: () -> Void
    let navigateBack: () -> Void
    let navigateForward: () -> Void
    let reopenClosedTab: () -> Void
    let openGemma: () -> Void
    let showExplorer: () -> Void
    let showGit: () -> Void
    let toggleAgentResponses: () -> Void
    let toggleLeftPanel: () -> Void
    let toggleWorkspacePanels: () -> Void
    let toggleRightPanel: () -> Void
    let zoomIn: () -> Void
    let zoomOut: () -> Void
    let actualSize: () -> Void
    let toggleFocusMode: () -> Void

    static func live(model: AppModel) -> AtelierActionHandlers {
        func showSidebarTab(_ tab: WorkspaceSidebarTab) {
            guard let workspace = model.workspace,
                  workspace.chrome.currentLayoutMode.docksSidebar else { return }
            workspace.chrome.selectedSidebarTab = tab
            if model.zoom.isFocusMode {
                model.zoom.toggleFocusMode()
            } else {
                workspace.chrome.showSidebarTab(tab)
            }
        }

        return AtelierActionHandlers(
            openFolder: model.chooseWorkspace,
            closeWorkspace: model.closeWorkspace,
            nextWorkspace: model.selectNextWorkspace,
            newTerminal: { model.workspace?.terminalTabs.add() },
            newClaudeCodeTerminal: { model.workspace?.terminalTabs.addAndRun("c") },
            newCodexTerminal: { model.workspace?.terminalTabs.addAndRun("cc") },
            closeTab: { model.workspace?.terminalTabs.closeSelectedTab() },
            navigateBack: { model.workspace?.terminalTabs.navigateBack() },
            navigateForward: { model.workspace?.terminalTabs.navigateForward() },
            reopenClosedTab: { model.workspace?.terminalTabs.reopenClosedTab() },
            openGemma: { model.workspace?.openGemma() },
            showExplorer: { showSidebarTab(.explorer) },
            showGit: { showSidebarTab(.sourceControl) },
            toggleAgentResponses: {
                guard let workspace = model.workspace else { return }
                workspace.chrome.toggleAgentResponses(
                    session: workspace,
                    windowController: model.windowController
                )
            },
            toggleLeftPanel: {
                guard let chrome = model.workspace?.chrome,
                      !model.zoom.isFocusMode,
                      chrome.currentLayoutMode.docksSidebar else { return }
                chrome.toggleSidebar()
            },
            toggleWorkspacePanels: {
                guard let chrome = model.workspace?.chrome else { return }
                if model.zoom.isFocusMode || chrome.panels.hasVisiblePanel {
                    model.zoom.toggleFocusMode()
                    return
                }
                chrome.applyPanelPresentation(
                    chrome.panels.togglingAllPanels(layout: chrome.currentLayoutMode),
                    requestsAnimation: true
                )
            },
            toggleRightPanel: {
                guard let chrome = model.workspace?.chrome,
                      !model.zoom.isFocusMode,
                      chrome.currentLayoutMode.supportsInspector else { return }
                chrome.toggleInspector(windowController: model.windowController)
            },
            zoomIn: {
                model.windowController.maximizeWorkspaceWindow()
                model.zoom.zoomIn()
            },
            zoomOut: model.zoom.zoomOut,
            actualSize: model.zoom.reset,
            toggleFocusMode: model.zoom.toggleFocusMode
        )
    }
}

nonisolated enum AtelierActionRegistry {
    static let actions: [AtelierActionDescriptor] = [
        AtelierActionDescriptor(
            id: .openFolder,
            title: "Open Folder...",
            category: "Workspace",
            systemImage: "folder",
            shortcutLabel: "Command-O"
        ),
        AtelierActionDescriptor(
            id: .closeWorkspace,
            title: "Close Workspace",
            category: "Workspace",
            systemImage: "xmark.rectangle",
            shortcutLabel: nil
        ),
        AtelierActionDescriptor(
            id: .nextWorkspace,
            title: "Next Workspace",
            category: "Workspace",
            systemImage: "arrow.right.square",
            shortcutLabel: "Command-`"
        ),
        AtelierActionDescriptor(
            id: .newTerminal,
            title: "New Terminal",
            category: "Terminal",
            systemImage: "terminal",
            shortcutLabel: "Command-T"
        ),
        AtelierActionDescriptor(
            id: .newClaudeCodeTerminal,
            title: "New Claude Code Terminal",
            category: "Terminal",
            systemImage: "terminal",
            shortcutLabel: "Command-Shift-,"
        ),
        AtelierActionDescriptor(
            id: .newCodexTerminal,
            title: "New Codex Terminal",
            category: "Terminal",
            systemImage: "terminal",
            shortcutLabel: "Command-Shift-."
        ),
        AtelierActionDescriptor(
            id: .closeTab,
            title: "Close Tab",
            category: "Tabs",
            systemImage: "xmark",
            shortcutLabel: "Command-W"
        ),
        AtelierActionDescriptor(
            id: .navigateBack,
            title: "Back",
            category: "Navigation",
            systemImage: "chevron.left",
            shortcutLabel: "Control--"
        ),
        AtelierActionDescriptor(
            id: .navigateForward,
            title: "Forward",
            category: "Navigation",
            systemImage: "chevron.right",
            shortcutLabel: "Control-Shift--"
        ),
        AtelierActionDescriptor(
            id: .reopenClosedTab,
            title: "Reopen Closed Tab",
            category: "Tabs",
            systemImage: "arrow.uturn.backward",
            shortcutLabel: nil
        ),
        AtelierActionDescriptor(
            id: .openGemma,
            title: "Open Gemma",
            category: "Agent",
            systemImage: "sparkles",
            shortcutLabel: nil
        ),
        AtelierActionDescriptor(
            id: .showExplorer,
            title: "Show Explorer",
            category: "View",
            systemImage: "folder",
            shortcutLabel: "Command-E"
        ),
        AtelierActionDescriptor(
            id: .showGit,
            title: "Show Git",
            category: "View",
            systemImage: "arrow.triangle.branch",
            shortcutLabel: "Command-R"
        ),
        AtelierActionDescriptor(
            id: .toggleAgentResponses,
            title: "Toggle Agent Responses",
            category: "View",
            systemImage: "text.bubble",
            shortcutLabel: "Command-Q"
        ),
        AtelierActionDescriptor(
            id: .toggleLeftPanel,
            title: "Toggle Left Panel",
            category: "View",
            systemImage: "sidebar.leading",
            shortcutLabel: "Command-Shift-E"
        ),
        AtelierActionDescriptor(
            id: .toggleWorkspacePanels,
            title: "Toggle Left and Right Panels",
            category: "View",
            systemImage: "rectangle.split.3x1",
            shortcutLabel: nil
        ),
        AtelierActionDescriptor(
            id: .toggleRightPanel,
            title: "Toggle Right Panel",
            category: "View",
            systemImage: "sidebar.trailing",
            shortcutLabel: "Command-Shift-R"
        ),
        AtelierActionDescriptor(
            id: .zoomIn,
            title: "Zoom In",
            category: "View",
            systemImage: "plus.magnifyingglass",
            shortcutLabel: "Command-+"
        ),
        AtelierActionDescriptor(
            id: .zoomOut,
            title: "Zoom Out",
            category: "View",
            systemImage: "minus.magnifyingglass",
            shortcutLabel: "Command--"
        ),
        AtelierActionDescriptor(
            id: .actualSize,
            title: "Actual Size",
            category: "View",
            systemImage: "1.magnifyingglass",
            shortcutLabel: nil
        ),
        AtelierActionDescriptor(
            id: .toggleFocusMode,
            title: "Enter Focus Mode",
            category: "View",
            systemImage: "rectangle.center.inset.filled",
            shortcutLabel: "Command-Shift-F"
        )
    ]

    static func descriptor(for id: AtelierActionID) -> AtelierActionDescriptor {
        guard let descriptor = actions.first(where: { $0.id == id }) else {
            assertionFailure("No descriptor registered for \(id.rawValue)")
            return AtelierActionDescriptor(
                id: id,
                title: id.rawValue,
                category: "",
                systemImage: "questionmark",
                shortcutLabel: nil
            )
        }
        return descriptor
    }

    static func title(for id: AtelierActionID, context: AtelierActionContext) -> String {
        if id == .toggleFocusMode, context.isFocusMode {
            return "Exit Focus Mode"
        }
        return descriptor(for: id).title
    }

    static func isEnabled(_ id: AtelierActionID, context: AtelierActionContext) -> Bool {
        switch id {
        case .openFolder, .actualSize, .toggleFocusMode:
            true
        case .closeWorkspace:
            context.canCloseWorkspace
        case .nextWorkspace:
            context.canCycleWorkspaces
        case .newTerminal,
             .newClaudeCodeTerminal,
             .newCodexTerminal,
             .openGemma,
             .toggleAgentResponses:
            context.hasWorkspace
        case .closeTab:
            context.canCloseTab
        case .navigateBack:
            context.canNavigateBack
        case .navigateForward:
            context.canNavigateForward
        case .reopenClosedTab:
            context.canReopenClosedTab
        case .showExplorer, .showGit:
            context.canShowSidebarTab
        case .toggleLeftPanel:
            context.canToggleLeftPanel
        case .toggleWorkspacePanels:
            context.canToggleWorkspacePanels
        case .toggleRightPanel:
            context.canToggleRightPanel
        case .zoomIn:
            context.canZoomIn
        case .zoomOut:
            context.canZoomOut
        }
    }

    @MainActor
    static func context(for model: AppModel) -> AtelierActionContext {
        AtelierActionContext(
            hasWorkspace: model.workspace != nil,
            canCloseWorkspace: model.selectedWorkspaceItem != nil,
            canCycleWorkspaces: model.workspaceItems.count > 1,
            canCloseTab: model.workspace?.terminalTabs.canCloseSelectedTab == true,
            canNavigateBack: model.workspace?.terminalTabs.canNavigateBack == true,
            canNavigateForward: model.workspace?.terminalTabs.canNavigateForward == true,
            canReopenClosedTab: model.workspace?.terminalTabs.canReopenClosedTab == true,
            canShowSidebarTab: model.workspace?.chrome.currentLayoutMode.docksSidebar == true,
            canToggleLeftPanel: model.workspace.map { workspace in
                !model.zoom.isFocusMode && workspace.chrome.currentLayoutMode.docksSidebar
            } ?? false,
            canToggleWorkspacePanels: model.workspace != nil,
            canToggleRightPanel: model.workspace.map { workspace in
                !model.zoom.isFocusMode && workspace.chrome.currentLayoutMode.supportsInspector
            } ?? false,
            canZoomIn: model.zoom.canZoomIn,
            canZoomOut: model.zoom.canZoomOut,
            isFocusMode: model.zoom.isFocusMode
        )
    }

    @MainActor
    static func perform(_ id: AtelierActionID, model: AppModel) {
        perform(id, handlers: .live(model: model))
    }

    @MainActor
    static func perform(_ id: AtelierActionID, handlers: AtelierActionHandlers) {
        switch id {
        case .openFolder:
            handlers.openFolder()
        case .closeWorkspace:
            handlers.closeWorkspace()
        case .nextWorkspace:
            handlers.nextWorkspace()
        case .newTerminal:
            handlers.newTerminal()
        case .newClaudeCodeTerminal:
            handlers.newClaudeCodeTerminal()
        case .newCodexTerminal:
            handlers.newCodexTerminal()
        case .closeTab:
            handlers.closeTab()
        case .navigateBack:
            handlers.navigateBack()
        case .navigateForward:
            handlers.navigateForward()
        case .reopenClosedTab:
            handlers.reopenClosedTab()
        case .openGemma:
            handlers.openGemma()
        case .showExplorer:
            handlers.showExplorer()
        case .showGit:
            handlers.showGit()
        case .toggleAgentResponses:
            handlers.toggleAgentResponses()
        case .toggleLeftPanel:
            handlers.toggleLeftPanel()
        case .toggleWorkspacePanels:
            handlers.toggleWorkspacePanels()
        case .toggleRightPanel:
            handlers.toggleRightPanel()
        case .zoomIn:
            handlers.zoomIn()
        case .zoomOut:
            handlers.zoomOut()
        case .actualSize:
            handlers.actualSize()
        case .toggleFocusMode:
            handlers.toggleFocusMode()
        }
    }
}
