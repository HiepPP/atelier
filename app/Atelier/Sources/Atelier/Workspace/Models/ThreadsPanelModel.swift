import Foundation
import Observation

nonisolated enum ThreadStatus: Equatable, Sendable {
    case running
    case done
}

nonisolated struct ThreadEntry: Equatable, Identifiable, Sendable {
    let terminalID: UUID
    let title: String
    let agentName: String
    let status: ThreadStatus
    let startedAt: Date
    let finishedAt: Date?

    var id: UUID { terminalID }
}

nonisolated struct WorkspaceThreadGroup: Equatable, Identifiable, Sendable {
    let workspaceID: String
    let name: String
    let threads: [ThreadEntry]

    var id: String { workspaceID }
}

nonisolated struct TerminalSnapshot: Equatable, Sendable {
    let terminalID: UUID
    let title: String
    let workspaceID: String
    let workspaceName: String
    let agentName: String?
}

/// A snapshot before its agent name is known. Gathering these is pure main-actor
/// property reading; resolving them costs two `sysctl` calls per terminal and
/// runs off the main actor.
nonisolated struct TerminalAgentProbe: Sendable {
    let terminalID: UUID
    let title: String
    let workspaceID: String
    let workspaceName: String
    let agentProbe: TerminalForegroundAgentProbe?
}

@MainActor
@Observable
final class ThreadsPanelModel {
    private struct RunState: Equatable {
        let agentName: String
        let status: ThreadStatus
        let startedAt: Date
        let finishedAt: Date?
    }

    private(set) var groups: [WorkspaceThreadGroup] = []
    private var runStates: [UUID: RunState] = [:]

    /// Main-actor phase: read terminal identity and PTY handles only.
    func makeProbes(sessions: [WorkspaceSession]) -> [TerminalAgentProbe] {
        sessions.flatMap { session in
            let workspaceID = session.state.id
            let workspaceName = WorkspaceRailIdentityPolicy.workspaceName(
                path: session.state.path
            )
            return session.terminalTabs.openTerminalTabs.map { terminal in
                TerminalAgentProbe(
                    terminalID: terminal.id,
                    title: terminal.title,
                    workspaceID: workspaceID,
                    workspaceName: workspaceName,
                    agentProbe: terminal.controller.foregroundAgentProbe
                )
            }
        }
    }

    /// Off-main phase: one `tcgetpgrp` plus two `sysctl` calls per terminal.
    nonisolated static func resolveSnapshots(
        probes: [TerminalAgentProbe]
    ) -> [TerminalSnapshot] {
        probes.map { probe in
            TerminalSnapshot(
                terminalID: probe.terminalID,
                title: probe.title,
                workspaceID: probe.workspaceID,
                workspaceName: probe.workspaceName,
                agentName: probe.agentProbe?.resolveAgentName()
            )
        }
    }

    func refresh(snapshots: [TerminalSnapshot], now: Date) {
        let liveTerminalIDs = Set(snapshots.map(\.terminalID))
        runStates = runStates.filter { liveTerminalIDs.contains($0.key) }

        for snapshot in snapshots {
            updateRunState(for: snapshot, now: now)
        }

        var snapshotsByWorkspace: [String: [TerminalSnapshot]] = [:]
        for snapshot in snapshots {
            snapshotsByWorkspace[snapshot.workspaceID, default: []].append(snapshot)
        }

        var seenWorkspaceIDs = Set<String>()
        let nextGroups = snapshots.compactMap { snapshot -> WorkspaceThreadGroup? in
            guard seenWorkspaceIDs.insert(snapshot.workspaceID).inserted else { return nil }
            let workspaceSnapshots = snapshotsByWorkspace[snapshot.workspaceID] ?? []
            let threads = workspaceSnapshots.compactMap { terminal -> ThreadEntry? in
                guard let state = runStates[terminal.terminalID] else { return nil }
                return ThreadEntry(
                    terminalID: terminal.terminalID,
                    title: terminal.title,
                    agentName: state.agentName,
                    status: state.status,
                    startedAt: state.startedAt,
                    finishedAt: state.finishedAt
                )
            }
            return WorkspaceThreadGroup(
                workspaceID: snapshot.workspaceID,
                name: snapshot.workspaceName,
                threads: threads
            )
        }

        if groups != nextGroups {
            groups = nextGroups
        }
    }

    private func updateRunState(for snapshot: TerminalSnapshot, now: Date) {
        switch (snapshot.agentName, runStates[snapshot.terminalID]) {
        case (.some(let agentName), .some(let current))
            where current.status == .running && current.agentName == agentName:
            return
        case (.some(let agentName), _):
            runStates[snapshot.terminalID] = RunState(
                agentName: agentName,
                status: .running,
                startedAt: now,
                finishedAt: nil
            )
        case (.none, .some(let current)) where current.status == .running:
            runStates[snapshot.terminalID] = RunState(
                agentName: current.agentName,
                status: .done,
                startedAt: current.startedAt,
                finishedAt: now
            )
        case (.none, _):
            return
        }
    }
}
