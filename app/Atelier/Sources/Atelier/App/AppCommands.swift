import SwiftUI

struct AppCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open Folder...") {
                model.chooseWorkspace()
            }
            .keyboardShortcut("o", modifiers: .command)

            Button("Close Workspace") {
                model.closeWorkspace()
            }
            .disabled(model.workspace == nil)
        }

        CommandGroup(after: .toolbar) {
            Button("Zoom In") {
                model.windowController.maximizeWorkspaceWindow()
                model.zoom.zoomIn()
            }
            .keyboardShortcut("+", modifiers: .command)
            .disabled(!model.zoom.canZoomIn)

            Button("Zoom Out") {
                model.zoom.zoomOut()
            }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(!model.zoom.canZoomOut)

            Button("Actual Size") {
                model.zoom.reset()
            }
            .keyboardShortcut("0", modifiers: .command)

            Button(model.zoom.isFocusMode ? "Exit Focus Mode" : "Enter Focus Mode") {
                model.zoom.toggleFocusMode()
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
        }
    }
}
