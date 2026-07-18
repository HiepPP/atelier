import Foundation

nonisolated enum AtelierActionID: String, CaseIterable, Identifiable, Sendable {
    case openFolder
    case closeWorkspace
    case newTerminal
    case closeTab
    case openGemma
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
    let canCloseTab: Bool
    let canZoomIn: Bool
    let canZoomOut: Bool
    let isFocusMode: Bool
}

@MainActor
struct AtelierActionHandlers {
    let openFolder: () -> Void
    let closeWorkspace: () -> Void
    let newTerminal: () -> Void
    let closeTab: () -> Void
    let openGemma: () -> Void
    let zoomIn: () -> Void
    let zoomOut: () -> Void
    let actualSize: () -> Void
    let toggleFocusMode: () -> Void

    static func live(model: AppModel) -> AtelierActionHandlers {
        AtelierActionHandlers(
            openFolder: model.chooseWorkspace,
            closeWorkspace: model.closeWorkspace,
            newTerminal: { model.workspace?.terminalTabs.add() },
            closeTab: { model.workspace?.terminalTabs.closeSelectedTab() },
            openGemma: { model.workspace?.openGemma() },
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
            id: .newTerminal,
            title: "New Terminal",
            category: "Terminal",
            systemImage: "terminal",
            shortcutLabel: "Command-T"
        ),
        AtelierActionDescriptor(
            id: .closeTab,
            title: "Close Tab",
            category: "Tabs",
            systemImage: "xmark",
            shortcutLabel: "Command-W"
        ),
        AtelierActionDescriptor(
            id: .openGemma,
            title: "Open Gemma",
            category: "Agent",
            systemImage: "sparkles",
            shortcutLabel: nil
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
            shortcutLabel: "Command-0"
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
        actions.first { $0.id == id }!
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
        case .closeWorkspace, .newTerminal, .openGemma:
            context.hasWorkspace
        case .closeTab:
            context.canCloseTab
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
            canCloseTab: model.workspace?.terminalTabs.canCloseSelectedTab == true,
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
        case .newTerminal:
            handlers.newTerminal()
        case .closeTab:
            handlers.closeTab()
        case .openGemma:
            handlers.openGemma()
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
