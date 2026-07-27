import AppKit
import SwiftUI

struct AppCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .appTermination) {
            Button("Quit Atelier") {
                NSApplication.shared.terminate(nil)
            }
        }

        CommandGroup(replacing: .saveItem) {
            Button(title(.closeTab)) {
                perform(.closeTab)
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(!isEnabled(.closeTab))
        }

        CommandGroup(after: .newItem) {
            Button(title(.openFolder)) {
                perform(.openFolder)
            }
            .keyboardShortcut("o", modifiers: .command)

            Button(title(.newTerminal)) {
                perform(.newTerminal)
            }
            .keyboardShortcut("t", modifiers: .command)
            .disabled(!isEnabled(.newTerminal))

            Button(title(.newClaudeCodeTerminal)) {
                perform(.newClaudeCodeTerminal)
            }
            .keyboardShortcut(",", modifiers: [.command, .shift])
            .disabled(!isEnabled(.newClaudeCodeTerminal))

            Button(title(.newCodexTerminal)) {
                perform(.newCodexTerminal)
            }
            .keyboardShortcut(".", modifiers: [.command, .shift])
            .disabled(!isEnabled(.newCodexTerminal))

            Button("New Empty Terminal") {
                perform(.newTerminal)
            }
            .keyboardShortcut(";", modifiers: [.command, .shift])
            .disabled(!isEnabled(.newTerminal))

            Button(title(.closeWorkspace)) {
                perform(.closeWorkspace)
            }
            .disabled(!isEnabled(.closeWorkspace))

            Button(title(.nextWorkspace)) {
                perform(.nextWorkspace)
            }
            .keyboardShortcut("`", modifiers: .command)
            .disabled(!isEnabled(.nextWorkspace))
        }

        CommandMenu("Workspaces") {
            Button("Open New Workspace...") {
                perform(.openFolder)
            }
            .keyboardShortcut("0", modifiers: .command)

            Divider()

            workspaceShortcut(1, key: "1")
            workspaceShortcut(2, key: "2")
            workspaceShortcut(3, key: "3")
            workspaceShortcut(4, key: "4")
            workspaceShortcut(5, key: "5")
            workspaceShortcut(6, key: "6")
            workspaceShortcut(7, key: "7")
            workspaceShortcut(8, key: "8")
            workspaceShortcut(9, key: "9")
        }

        CommandGroup(after: .toolbar) {
            Button(title(.navigateBack)) {
                perform(.navigateBack)
            }
            .keyboardShortcut("-", modifiers: .control)
            .disabled(!isEnabled(.navigateBack))

            Button(title(.navigateForward)) {
                perform(.navigateForward)
            }
            .keyboardShortcut("-", modifiers: [.control, .shift])
            .disabled(!isEnabled(.navigateForward))

            Button(title(.reopenClosedTab)) {
                perform(.reopenClosedTab)
            }
            .disabled(!isEnabled(.reopenClosedTab))

            Button(title(.showExplorer)) {
                perform(.showExplorer)
            }
            .disabled(!isEnabled(.showExplorer))

            Button(title(.showGit)) {
                perform(.showGit)
            }
            .disabled(!isEnabled(.showGit))

            Button(title(.toggleExplorerGit)) {
                perform(.toggleExplorerGit)
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(!isEnabled(.toggleExplorerGit))

            Button(title(.toggleAgentResponses)) {
                perform(.toggleAgentResponses)
            }
            .keyboardShortcut("q", modifiers: .command)
            .disabled(!isEnabled(.toggleAgentResponses))

            Button(title(.toggleLeftPanel)) {
                perform(.toggleLeftPanel)
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(!isEnabled(.toggleLeftPanel))

            Button(title(.toggleRightPanel)) {
                perform(.toggleRightPanel)
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(!isEnabled(.toggleRightPanel))

            Divider()

            Button(title(.zoomIn)) {
                perform(.zoomIn)
            }
            .keyboardShortcut("+", modifiers: .command)
            .disabled(!isEnabled(.zoomIn))

            Button(title(.zoomOut)) {
                perform(.zoomOut)
            }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(!isEnabled(.zoomOut))

            Button(title(.actualSize)) {
                perform(.actualSize)
            }

            Button(title(.toggleFocusMode)) {
                perform(.toggleFocusMode)
            }
        }
    }

    private var context: AtelierActionContext {
        AtelierActionRegistry.context(for: model)
    }

    private func title(_ id: AtelierActionID) -> String {
        AtelierActionRegistry.title(for: id, context: context)
    }

    private func isEnabled(_ id: AtelierActionID) -> Bool {
        AtelierActionRegistry.isEnabled(id, context: context)
    }

    private func perform(_ id: AtelierActionID) {
        AtelierActionRegistry.perform(id, model: model)
    }

    private func workspaceShortcut(_ number: Int, key: KeyEquivalent) -> some View {
        Button(workspaceShortcutTitle(number)) {
            model.selectWorkspace(shortcutNumber: number)
        }
        .keyboardShortcut(key, modifiers: .command)
        .disabled(!hasWorkspace(shortcutNumber: number))
    }

    private func workspaceShortcutTitle(_ number: Int) -> String {
        guard let index = WorkspaceRailShortcutPolicy.index(for: number),
              model.workspaceItems.indices.contains(index) else {
            return "Workspace \(number)"
        }
        let item = model.workspaceItems[index]
        let name = WorkspaceRailIdentityPolicy.workspaceName(path: item.state.path)
        return "Workspace \(number): \(name)"
    }

    private func hasWorkspace(shortcutNumber: Int) -> Bool {
        guard let index = WorkspaceRailShortcutPolicy.index(for: shortcutNumber) else {
            return false
        }
        return model.workspaceItems.indices.contains(index)
    }
}

struct AtelierPaletteCommands: Commands {
    @FocusedValue(\.showQuickOpen) private var showQuickOpen
    @FocusedValue(\.showWorkspaceSearch) private var showWorkspaceSearch
    @FocusedValue(\.showCommandPalette) private var showCommandPalette

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Quick Open...") {
                showQuickOpen?()
            }
            .keyboardShortcut("p", modifiers: .command)
            .disabled(showQuickOpen == nil)

            Button("Search All Files...") {
                showWorkspaceSearch?()
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(showWorkspaceSearch == nil)

            Button("Command Palette...") {
                showCommandPalette?()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(showCommandPalette == nil)
        }
    }
}

private struct ShowQuickOpenKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct ShowWorkspaceSearchKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct ShowCommandPaletteKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var showQuickOpen: (() -> Void)? {
        get { self[ShowQuickOpenKey.self] }
        set { self[ShowQuickOpenKey.self] = newValue }
    }

    var showWorkspaceSearch: (() -> Void)? {
        get { self[ShowWorkspaceSearchKey.self] }
        set { self[ShowWorkspaceSearchKey.self] = newValue }
    }

    var showCommandPalette: (() -> Void)? {
        get { self[ShowCommandPaletteKey.self] }
        set { self[ShowCommandPaletteKey.self] = newValue }
    }
}
