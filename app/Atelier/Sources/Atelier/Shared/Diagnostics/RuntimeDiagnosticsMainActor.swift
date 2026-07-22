import AppKit
import Foundation

@MainActor
extension AppModel {
    func runtimeDiagnosticsSnapshot() -> RuntimeMainSnapshot {
        guard let workspace else { return RuntimeMainSnapshot() }
        var snapshot = workspace.terminalTabs.runtimeDiagnosticsSnapshot(
            workspaceRoot: workspace.rootURL
        )
        snapshot.fileTree = RuntimeFileTreeMetricsStore.shared.snapshot(
            rootPath: workspace.rootURL.standardizedFileURL.path
        )
        snapshot.editor.expectedControllerCount = liveSessions.reduce(into: 0) { count, session in
            count += session.terminalTabs.fileTabCount
        }

        var terminal = RuntimeTerminalSnapshot()
        for session in liveSessions {
            for tab in session.terminalTabs.openTerminalTabs {
                let metric = tab.controller.runtimeDiagnosticsMetric()
                terminal.controllerCount += 1
                if metric.active { terminal.activeControllerCount += 1 }
                if metric.attached { terminal.attachedControllerCount += 1 }
                if terminal.controllers.count < RuntimeTerminalSnapshot.controllerCapacity {
                    terminal.controllers.append(metric)
                }
                if session === workspace, tab.id == workspace.terminalTabs.selectedID {
                    terminal.selectedControllerID = metric.id
                }
                if metric.firstResponder {
                    terminal.firstResponderControllerID = metric.id
                    terminal.firstResponderWorkspaceRootName = metric.workspaceRootName
                }
            }
        }
        if terminal.firstResponderControllerID != nil {
            terminal.firstResponderKind = "terminal"
        } else if NSApp.keyWindow?.firstResponder != nil {
            terminal.firstResponderKind = "nonTerminal"
        }
        snapshot.terminal = terminal
        return snapshot
    }

    func handleRuntimeProbe(_ request: RuntimeProbeRequest) async -> RuntimeProbeResponse {
        let clock = SystemRuntimeMonotonicClock()
        let startedAt = clock.now()
        let response: (
            status: String,
            result: [String: RuntimeScalar],
            editor: RuntimeEditorSnapshot?,
            error: String?
        )
        switch request.command {
        case .main:
            response = (
                "ok",
                [
                    "timeout": .boolean(false),
                    "heartbeatAgeMs": .double(
                        RuntimeDiagnosticsService.shared.currentHeartbeatAgeMilliseconds()
                    )
                ],
                nil,
                nil
            )
        case .editor:
            guard let editorSession = workspace?.terminalTabs.selectedEditor else {
                response = (
                    "notApplicable",
                    ["reason": .string("Selected tab is not a text editor.")],
                    nil,
                    nil
                )
                break
            }
            response = ("ok", [:], enrichedRuntimeEditorSnapshot(editorSession), nil)
        case .editorScroll:
            guard let editorSession = workspace?.terminalTabs.selectedEditor else {
                response = (
                    "notApplicable",
                    ["reason": .string("Selected tab is not a text editor.")],
                    nil,
                    nil
                )
                break
            }
            let delta = request.arguments["delta"]?.doubleValue ?? 400
            let restore = request.arguments["restore"]?.boolValue ?? false
            let probe = await editorSession.runRuntimeScrollProbe(delta: delta, restore: restore)
            response = (probe.status, probe.result, enrichedRuntimeEditorSnapshot(editorSession), nil)
        }
        return RuntimeProbeResponse(
            schemaVersion: 1,
            id: request.id,
            command: request.command,
            status: response.status,
            completedAt: Date().formatted(
                .iso8601.year().month().day().time(includingFractionalSeconds: true)
                    .timeZone(separator: .colon)
            ),
            elapsedMs: max(0, clock.now() - startedAt) * 1_000,
            result: response.result,
            editor: response.editor,
            error: response.error
        )
    }

    private func enrichedRuntimeEditorSnapshot(
        _ editorSession: EditorSession
    ) -> RuntimeEditorSnapshot {
        var editor = editorSession.runtimeEditorSnapshot()
        editor.liveControllerCount = RuntimeDiagnosticsService.shared.currentLiveControllerCount()
        editor.expectedControllerCount = liveSessions.reduce(into: 0) { count, session in
            count += session.terminalTabs.fileTabCount
        }
        return editor
    }
}

nonisolated private extension RuntimeScalar {
    var doubleValue: Double? {
        switch self {
        case .double(let value): value
        case .integer(let value): Double(value)
        case .string, .boolean: nil
        }
    }

    var boolValue: Bool? {
        if case .boolean(let value) = self { return value }
        return nil
    }
}
