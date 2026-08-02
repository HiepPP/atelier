import AppKit
import Foundation

@MainActor
extension AppModel {
    func runtimeDiagnosticsSnapshot() -> RuntimeMainSnapshot {
        let chrome = runtimeChromeSnapshot()
        guard let workspace else {
            var empty = RuntimeMainSnapshot()
            empty.chrome = chrome
            return empty
        }
        var snapshot = workspace.terminalTabs.runtimeDiagnosticsSnapshot(
            workspaceRoot: workspace.rootURL
        )
        snapshot.chrome = chrome
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
        case .chrome:
            let chrome = runtimeChromeSnapshot()
            response = (
                "ok",
                [
                    "selectedSidebarTab": .string(chrome.selectedSidebarTab),
                    "showsSidebar": .boolean(chrome.showsSidebar),
                    "showsInspector": .boolean(chrome.showsInspector),
                    "restoresSidebarAfterInspector":
                        .boolean(chrome.restoresSidebarAfterInspector),
                    "layoutMode": .string(chrome.layoutMode),
                    "hasAppliedInitialLayout": .boolean(chrome.hasAppliedInitialLayout),
                    "sessionCount": .integer(chrome.sessionCount),
                    "sessionsInSync": .boolean(chrome.sessionsInSync)
                ],
                nil,
                nil
            )
        case .diff:
            guard let tabs = workspace?.terminalTabs else {
                response = (
                    "notApplicable",
                    ["reason": .string("No active workspace.")],
                    nil,
                    nil
                )
                break
            }
            var result: [String: RuntimeScalar] = [
                "selectedTabKind": .string(tabs.selectedTabKind ?? "none"),
                "gitDiffTabCount": .integer(tabs.gitDiffTabCount)
            ]
            result.merge(Self.diffProbeMetrics(tabs.selectedGitDiff)) { _, new in new }
            response = ("ok", result, nil, nil)
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

    /// Read-only view of the selected diff tab. Reports the same numbers the
    /// truncation footer renders, so diff UI state is checkable from the CLI
    /// instead of the accessibility tree. Paths stay workspace-relative and no
    /// diff content is reported.
    static func diffProbeMetrics(_ session: GitDiffSession?) -> [String: RuntimeScalar] {
        guard let session else { return ["diffState": .string("noSelectedDiff")] }
        var result: [String: RuntimeScalar] = [
            "diffPath": .string(session.selection.change.path),
            "diffStaged": .boolean(session.selection.staged),
            "showsFullDiff": .boolean(session.showsFullDiff),
            "needsReload": .boolean(session.needsReload)
        ]
        switch session.state {
        case .loading:
            result["diffState"] = .string("loading")
        case .loaded(let document):
            result["diffState"] = .string("loaded")
            result["lineCount"] = .integer(document.lines.count)
            result["hiddenLineCount"] = .integer(document.hiddenLineCount)
            result["additions"] = .integer(document.additions)
            result["deletions"] = .integer(document.deletions)
            result["showsTruncationFooter"] = .boolean(document.hiddenLineCount > 0)
        case .image(let data):
            result["diffState"] = .string("image")
            result["imageBytes"] = .integer(data.count)
        case .message:
            result["diffState"] = .string("message")
        case .failed:
            result["diffState"] = .string("failed")
        }
        return result
    }

    /// Read-only view of the window chrome. Reads the shared owner directly and
    /// compares every mounted session against it, so a workspace switch that
    /// moved a panel or the sidebar tab would show as `sessionsInSync: false`
    /// without driving the accessibility tree.
    private func runtimeChromeSnapshot() -> RuntimeChromeSnapshot {
        let sessions = liveSessions
        let expected = chromeShared.layoutProfilePanelState
        return RuntimeChromeSnapshot(
            selectedSidebarTab: chromeShared.selectedSidebarTab.rawValue,
            showsSidebar: chromeShared.panels.showsSidebar,
            showsInspector: chromeShared.panels.showsInspector,
            restoresSidebarAfterInspector: chromeShared.panels.restoresSidebarAfterInspector,
            layoutMode: Self.layoutModeName(chromeShared.currentLayoutMode),
            hasAppliedInitialLayout: chromeShared.hasAppliedInitialLayout,
            sessionCount: sessions.count,
            sessionsInSync: sessions.allSatisfy { $0.chrome.layoutProfilePanelState == expected }
        )
    }

    private static func layoutModeName(_ mode: WorkspaceLayoutMode) -> String {
        switch mode {
        case .compact: "compact"
        case .standard: "standard"
        case .wide: "wide"
        }
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
