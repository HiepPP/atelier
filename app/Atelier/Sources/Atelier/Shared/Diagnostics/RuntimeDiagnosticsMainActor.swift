import Foundation

@MainActor
extension AppModel {
    func runtimeDiagnosticsSnapshot() -> RuntimeMainSnapshot {
        guard let workspace else { return RuntimeMainSnapshot() }
        return workspace.terminalTabs.runtimeDiagnosticsSnapshot(
            workspaceRoot: workspace.rootURL
        )
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
        editor.expectedControllerCount = workspace.map {
            $0.terminalTabs.runtimeDiagnosticsSnapshot(workspaceRoot: $0.rootURL)
                .workspace.fileTabCount
        } ?? 0
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
