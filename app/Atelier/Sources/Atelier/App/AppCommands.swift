import SwiftUI

struct AppCommands: Commands {
    let model: AppModel

    var body: some Commands {
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

            Button(title(.closeWorkspace)) {
                perform(.closeWorkspace)
            }
            .disabled(!isEnabled(.closeWorkspace))
        }

        CommandGroup(after: .toolbar) {
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
            .keyboardShortcut("0", modifiers: .command)

            Button(title(.toggleFocusMode)) {
                perform(.toggleFocusMode)
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
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
}

struct AtelierPaletteCommands: Commands {
    @FocusedValue(\.showQuickOpen) private var showQuickOpen
    @FocusedValue(\.showCommandPalette) private var showCommandPalette

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Quick Open...") {
                showQuickOpen?()
            }
            .keyboardShortcut("p", modifiers: .command)
            .disabled(showQuickOpen == nil)

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

private struct ShowCommandPaletteKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var showQuickOpen: (() -> Void)? {
        get { self[ShowQuickOpenKey.self] }
        set { self[ShowQuickOpenKey.self] = newValue }
    }

    var showCommandPalette: (() -> Void)? {
        get { self[ShowCommandPaletteKey.self] }
        set { self[ShowCommandPaletteKey.self] = newValue }
    }
}
